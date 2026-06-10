"""
Pytest configuration for ml-service smoke tests.

Why this file exists:
  `ml-service/app/config.py` calls `sys.exit(1)` at import time if
  SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY / SUPABASE_JWT_SECRET are unset.
  That's the right behavior for production (fail closed) but it means
  every pytest test that imports `app.main` would fail to even reach
  the test body — pytest would die during collection.

  This conftest sets dummy values for those env vars *before* any test
  module imports the app. The dummy JWT secret is also used by
  `test_auth.py` to mint valid test tokens via PyJWT.

  These dummies must NEVER appear in any production env. The strings
  below are clearly synthetic.
"""

import os
import sys

# Must set BEFORE any `from app.<x>` import in any test module.
os.environ.setdefault("SUPABASE_URL", "https://ci-dummy.supabase.co")

# Must be JWT-shaped (header.payload.signature) — supabase-py validates this
# at create_client() time and we want imports to succeed. Decoded payload:
# {"role":"service_role"}. Signature is obviously fake.
os.environ.setdefault(
    "SUPABASE_SERVICE_ROLE_KEY",
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    ".eyJyb2xlIjoic2VydmljZV9yb2xlIn0"
    ".ci-dummy-not-real-signature-do-not-use-in-prod",
)
os.environ.setdefault(
    "SUPABASE_JWT_SECRET",
    "ci-dummy-jwt-secret-DO-NOT-USE-IN-PROD-32chars",
)
os.environ.setdefault("ALLOWED_ORIGINS", "http://localhost:3000")
os.environ.setdefault("SENTRY_DSN", "")  # disable Sentry init

# Ensure the parent dir is on sys.path so `from app...` works without
# an installed package.
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)
