"""JWT authentication middleware for the ML service.

Validates Supabase JWTs on every request (except /health).
The token's `sub` claim must match the `user_id` in the request body,
preventing users from querying other users' data.
"""

import jwt
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import SUPABASE_JWT_SECRET

# Paths that don't require authentication
PUBLIC_PATHS = {"/health", "/docs", "/openapi.json"}


class JWTAuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.method == "OPTIONS" or request.url.path in PUBLIC_PATHS:
            return await call_next(request)

        auth_header = request.headers.get("authorization", "")
        if not auth_header.startswith("Bearer "):
            raise HTTPException(status_code=401, detail="Missing or invalid Authorization header")

        token = auth_header.removeprefix("Bearer ")
        try:
            payload = jwt.decode(
                token,
                SUPABASE_JWT_SECRET,
                algorithms=["HS256"],
                audience="authenticated",
            )
        except jwt.ExpiredSignatureError:
            raise HTTPException(status_code=401, detail="Token expired")
        except jwt.InvalidTokenError as e:
            raise HTTPException(status_code=401, detail=f"Invalid token: {e}")

        # Attach the authenticated user id to request state
        request.state.user_id = payload.get("sub", "")
        return await call_next(request)
