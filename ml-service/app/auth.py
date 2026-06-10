"""JWT authentication middleware for the ML service.

Validates Supabase JWTs on every request (except PUBLIC_PATHS).
The token's `sub` claim is attached to `request.state.user_id` so
downstream handlers can authorize against it.

Important: this middleware returns a `JSONResponse` directly rather than
raising `HTTPException`. Starlette's `BaseHTTPMiddleware` does NOT route
exceptions through FastAPI's exception handlers — a raised HTTPException
bubbles all the way out as a 500. Returning the Response directly is the
documented pattern for middleware-side rejections.
(Verified by W1.4 smoke tests in tests/test_auth.py.)
"""

import jwt
from fastapi import Request
from fastapi.responses import JSONResponse
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import SUPABASE_JWT_SECRET, SUPABASE_URL

# Paths that don't require authentication.
# DO NOT add /predict-*, /injury-risk, or /training-summary here —
# they carry user PII and must always require a JWT.
PUBLIC_PATHS = {"/health", "/docs", "/openapi.json"}


def _reject(status_code: int, detail: str) -> JSONResponse:
    """Build a 401-shaped JSON response. Standard FastAPI 401 body shape so
    iOS/web clients can parse `detail` uniformly across all 401 sources."""
    return JSONResponse(status_code=status_code, content={"detail": detail})


class JWTAuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.method == "OPTIONS" or request.url.path in PUBLIC_PATHS:
            return await call_next(request)

        auth_header = request.headers.get("authorization", "")
        if not auth_header.startswith("Bearer "):
            return _reject(401, "Missing or invalid Authorization header")

        token = auth_header.removeprefix("Bearer ")
        expected_issuer = f"{SUPABASE_URL}/auth/v1" if SUPABASE_URL else None
        try:
            payload = jwt.decode(
                token,
                SUPABASE_JWT_SECRET,
                algorithms=["HS256"],
                audience="authenticated",
                issuer=expected_issuer,
                options={"verify_iss": bool(expected_issuer)},
            )
        except jwt.ExpiredSignatureError:
            return _reject(401, "Token expired")
        except jwt.InvalidTokenError as e:
            return _reject(401, f"Invalid token: {e}")

        # Attach the authenticated user id to request state for downstream
        # handlers to authorize against.
        request.state.user_id = payload.get("sub", "")
        return await call_next(request)
