# Sentry must initialize before FastAPI is constructed so its
# ASGI middleware wraps every request handler.
from app.config import SENTRY_DSN, SENTRY_ENV

if SENTRY_DSN:
    import sentry_sdk
    from sentry_sdk.integrations.fastapi import FastApiIntegration
    sentry_sdk.init(
        dsn=SENTRY_DSN,
        environment=SENTRY_ENV,
        traces_sample_rate=0.1,
        integrations=[FastApiIntegration()],
    )

from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded

from app.auth import JWTAuthMiddleware
from app.config import ALLOWED_ORIGINS
from app.db import fetch_workout_features, fetch_race_results, fetch_fitness_snapshots
from app.predictor import predictor
from app.injury_risk import compute_injury_risk


def _rate_limit_key(request: Request) -> str:
    """Use the authenticated user's JWT sub claim as the rate-limit key."""
    return getattr(request.state, "user_id", request.client.host if request.client else "anon")


limiter = Limiter(key_func=_rate_limit_key)

app = FastAPI(
    title="Running ML Service",
    description="ML-powered fitness predictions and injury risk scoring",
    version="0.1.0",
)

app.state.limiter = limiter


@app.exception_handler(RateLimitExceeded)
async def _rate_limit_handler(request: Request, exc: RateLimitExceeded):
    return JSONResponse(
        status_code=429,
        content={"detail": f"Rate limit exceeded: {exc.detail}. Please wait and try again."},
    )


# Auth middleware must be added before CORS so preflight OPTIONS bypass auth
app.add_middleware(JWTAuthMiddleware)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["authorization", "content-type"],
)


class PredictRequest(BaseModel):
    user_id: str
    days: int = Field(default=180, ge=1, le=730)


class InjuryRiskRequest(BaseModel):
    user_id: str
    days: int = Field(default=60, ge=1, le=365)


def _enforce_ownership(request: Request, requested_user_id: str):
    """Ensure the JWT subject matches the requested user_id."""
    authed_uid = getattr(request.state, "user_id", None)
    if authed_uid != requested_user_id:
        raise HTTPException(status_code=403, detail="Cannot access another user's data")


@app.get("/health")
def health():
    return {
        "status": "ok",
        "model_loaded": predictor.model is not None,
        "version": "0.1.0",
    }


@app.post("/predict-fitness")
@limiter.limit("10/minute")
def predict_fitness(req: PredictRequest, request: Request):
    _enforce_ownership(request, req.user_id)
    features = fetch_workout_features(req.user_id, days=req.days)
    races = fetch_race_results(req.user_id)
    result = predictor.predict(features, races)
    return result


@app.post("/injury-risk")
@limiter.limit("10/minute")
def injury_risk(req: InjuryRiskRequest, request: Request):
    _enforce_ownership(request, req.user_id)
    features = fetch_workout_features(req.user_id, days=req.days)
    result = compute_injury_risk(features)
    return result


@app.post("/training-summary")
@limiter.limit("30/minute")
def training_summary(req: PredictRequest, request: Request):
    """Quick training load summary without predictions."""
    _enforce_ownership(request, req.user_id)
    features = fetch_workout_features(req.user_id, days=req.days)
    if not features:
        raise HTTPException(status_code=404, detail="No workout data found")

    recent_14 = features[-14:] if len(features) >= 14 else features
    latest = features[-1]

    weekly_miles = sum(f.get("total_distance_miles", 0) or 0 for f in recent_14) / max(len(recent_14) / 7, 1)
    weekly_hard = sum(f.get("hard_effort_minutes", 0) or 0 for f in recent_14) / max(len(recent_14) / 7, 1)
    weekly_runs = len(recent_14) / max(len(recent_14) / 7, 1) * 7 / max(len(recent_14), 1)

    return {
        "workout_count": len(features),
        "weekly_miles": round(weekly_miles, 1),
        "weekly_hard_minutes": round(weekly_hard, 1),
        "acwr": latest.get("acwr"),
        "monotony": latest.get("monotony_7d"),
        "strain": latest.get("strain_7d"),
        "rolling_7d_miles": latest.get("rolling_7d_miles"),
        "rolling_28d_miles": latest.get("rolling_28d_miles"),
    }
