"""
W1.4 smoke test: /health is publicly reachable.

Asserts:
  - GET /health without an Authorization header returns 200.
  - The response body has the documented shape (status / model_loaded / version).
  - The endpoint is in PUBLIC_PATHS so JWTAuthMiddleware lets it through.
"""

from fastapi.testclient import TestClient

from app.main import app
from app.auth import PUBLIC_PATHS


def test_health_is_in_public_paths():
    """If this fails, the middleware will demand a JWT for /health and
    every Railway healthcheck will start failing silently."""
    assert "/health" in PUBLIC_PATHS, (
        "JWTAuthMiddleware.PUBLIC_PATHS must include /health so the platform "
        "health probe doesn't get 401s."
    )


def test_health_returns_200_without_auth():
    client = TestClient(app)
    resp = client.get("/health")
    assert resp.status_code == 200, (
        f"/health should be 200 without auth; got {resp.status_code} {resp.text}"
    )


def test_health_body_shape():
    client = TestClient(app)
    resp = client.get("/health")
    body = resp.json()
    assert body.get("status") == "ok"
    assert "model_loaded" in body, "health body must expose model_loaded"
    assert "version" in body, "health body must expose version"
