import os
import sys
from dotenv import load_dotenv

load_dotenv()

SUPABASE_URL = os.getenv("SUPABASE_URL", "")
SUPABASE_SERVICE_ROLE_KEY = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "")
SUPABASE_JWT_SECRET = os.getenv("SUPABASE_JWT_SECRET", "")
PORT = int(os.getenv("PORT", "8000"))
MODEL_DIR = os.path.join(os.path.dirname(__file__), "..", "models")

# Sentry — optional. Not setting SENTRY_DSN disables error reporting.
SENTRY_DSN = os.getenv("SENTRY_DSN", "")
SENTRY_ENV = os.getenv("RAILWAY_ENVIRONMENT") or os.getenv("ENV", "development")

# Allowed CORS origins — set via comma-separated env var in production
ALLOWED_ORIGINS = [
    o.strip()
    for o in os.getenv("ALLOWED_ORIGINS", "http://localhost:3000").split(",")
    if o.strip()
]

# Validate required env vars at import time
_REQUIRED = {
    "SUPABASE_URL": SUPABASE_URL,
    "SUPABASE_SERVICE_ROLE_KEY": SUPABASE_SERVICE_ROLE_KEY,
    "SUPABASE_JWT_SECRET": SUPABASE_JWT_SECRET,
}
_missing = [k for k, v in _REQUIRED.items() if not v]
if _missing:
    print(f"FATAL: Missing required environment variables: {', '.join(_missing)}", file=sys.stderr)
    sys.exit(1)
