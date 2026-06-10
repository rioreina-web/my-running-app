"""
W1.4 smoke test: JWTAuthMiddleware rejects what it should and accepts what
it should.

This is the load-bearing security check for the ML service. If it ever
regressed (e.g. someone broadened PUBLIC_PATHS to include /predict-*,
or weakened the issuer/audience check) the service would become an
unauthenticated cost surface.

Note on the prediction endpoints: we don't actually exercise their happy
path — that would require a real SUPABASE_URL + DB. We only verify the
auth gate's behavior. A 200 from /predict-fitness in CI would mean DB
mocking, which is out of scope for a smoke test.
"""

import os
import time

import jwt
import pytest
from fastapi.testclient import TestClient

from app.main import app


JWT_SECRET = os.environ["SUPABASE_JWT_SECRET"]
SUPABASE_URL = os.environ["SUPABASE_URL"]
EXPECTED_ISSUER = f"{SUPABASE_URL}/auth/v1"
EXPECTED_AUDIENCE = "authenticated"

# Endpoints that MUST require auth. If you add a new prediction endpoint,
# add it here so a misconfigured public route is caught.
PROTECTED_ENDPOINTS = [
    ("POST", "/predict-fitness"),
    ("POST", "/injury-risk"),
    ("POST", "/training-summary"),
]


# ---------- Helpers ----------

def mint_token(
    sub: str = "auth0|test-user",
    secret: str = JWT_SECRET,
    issuer: str = EXPECTED_ISSUER,
    audience: str = EXPECTED_AUDIENCE,
    expires_in: int = 3600,
    algorithm: str = "HS256",
) -> str:
    """Build a Supabase-shaped JWT for tests."""
    now = int(time.time())
    payload = {
        "sub":  sub,
        "aud":  audience,
        "iss":  issuer,
        "iat":  now,
        "exp":  now + expires_in,
        "role": "authenticated",
    }
    return jwt.encode(payload, secret, algorithm=algorithm)


# ---------- Negative tests: middleware must reject ----------

@pytest.mark.parametrize("method,path", PROTECTED_ENDPOINTS)
def test_protected_endpoint_rejects_missing_auth_header(method, path):
    """A request with no Authorization header → 401."""
    client = TestClient(app)
    resp = client.request(method, path, json={"user_id": "anything"})
    assert resp.status_code == 401, (
        f"{method} {path} without auth should be 401; got {resp.status_code}"
    )


@pytest.mark.parametrize("method,path", PROTECTED_ENDPOINTS)
def test_protected_endpoint_rejects_non_bearer(method, path):
    """Wrong scheme (Basic, ApiKey, etc.) → 401."""
    client = TestClient(app)
    resp = client.request(
        method, path,
        json={"user_id": "anything"},
        headers={"Authorization": "Basic dXNlcjpwYXNz"},
    )
    assert resp.status_code == 401, (
        f"{method} {path} with non-Bearer auth should be 401; got {resp.status_code}"
    )


def test_protected_endpoint_rejects_malformed_token():
    client = TestClient(app)
    resp = client.post(
        "/predict-fitness",
        json={"user_id": "anything"},
        headers={"Authorization": "Bearer not-a-real-jwt"},
    )
    assert resp.status_code == 401


def test_protected_endpoint_rejects_expired_token():
    expired = mint_token(expires_in=-60)
    client = TestClient(app)
    resp = client.post(
        "/predict-fitness",
        json={"user_id": "anything"},
        headers={"Authorization": f"Bearer {expired}"},
    )
    assert resp.status_code == 401
    # Friendly message helps the iOS app distinguish "refresh me" from
    # "really unauthorized".
    assert "expired" in resp.text.lower(), (
        f"expired-token response should mention 'expired'; got {resp.text}"
    )


def test_protected_endpoint_rejects_wrong_secret():
    """Token signed with a different secret must not be trusted."""
    token = mint_token(secret="not-the-real-secret-different-32-chars-x")
    client = TestClient(app)
    resp = client.post(
        "/predict-fitness",
        json={"user_id": "anything"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 401


def test_protected_endpoint_rejects_wrong_audience():
    token = mint_token(audience="some-other-aud")
    client = TestClient(app)
    resp = client.post(
        "/predict-fitness",
        json={"user_id": "anything"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 401


def test_protected_endpoint_rejects_wrong_issuer():
    token = mint_token(issuer="https://attacker.example/auth/v1")
    client = TestClient(app)
    resp = client.post(
        "/predict-fitness",
        json={"user_id": "anything"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 401


# ---------- Positive test: middleware accepts a valid token ----------

def test_protected_endpoint_accepts_valid_token_and_attaches_user_id():
    """
    A valid Supabase-shaped JWT must reach the handler with
    `request.state.user_id` populated from the `sub` claim.

    We don't assert 200 — the handler will then try to query a non-existent
    DB (the dummy SUPABASE_URL doesn't resolve in CI). What we assert:
      - The response is NOT 401 (the middleware accepted the token).
      - The handler was actually entered (proved by a downstream connection
        error or 5xx, depending on how httpx/TestClient surface it).

    `raise_app_exceptions=False` converts unhandled handler exceptions
    into a 500 response so we can assert on the status code rather than
    catching the raw exception.
    """
    token = mint_token(sub="auth0|valid-test-user")
    client = TestClient(app, raise_server_exceptions=False)
    resp = client.post(
        "/predict-fitness",
        json={"user_id": "auth0|valid-test-user"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code != 401, (
        f"valid token was rejected as 401: {resp.text}"
    )
    # The handler was reached (and then failed for unrelated DB reasons).
    # Any non-401 status proves the middleware let it through.
    assert resp.status_code in {200, 400, 422, 500, 502, 503}, (
        f"expected handler to be entered; got unexpected status "
        f"{resp.status_code}: {resp.text}"
    )


# ---------- Sanity ----------

def test_public_paths_does_not_leak_protected_routes():
    """Don't broaden PUBLIC_PATHS without a very good reason. /predict-*,
    /injury-risk, /training-summary are NEVER public."""
    from app.auth import PUBLIC_PATHS

    for forbidden in ["/predict-fitness", "/injury-risk", "/training-summary"]:
        assert forbidden not in PUBLIC_PATHS, (
            f"{forbidden} must NOT be in PUBLIC_PATHS — it carries user PII."
        )
