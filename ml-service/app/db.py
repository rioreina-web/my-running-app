import logging

from postgrest.exceptions import APIError
from supabase import create_client

from app.config import SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

log = logging.getLogger(__name__)

supabase = create_client(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)


def fetch_workout_features(user_id: str, days: int = 180) -> list[dict]:
    """Fetch workout features for a user, ordered by date."""
    from datetime import datetime, timedelta

    cutoff = (datetime.utcnow() - timedelta(days=days)).isoformat()

    try:
        result = (
            supabase.table("workout_features")
            .select("*")
            .eq("user_id", user_id)
            .gte("workout_date", cutoff)
            .order("workout_date", desc=False)
            .execute()
        )
        return result.data or []
    except APIError as e:
        log.warning(f"workout_features query failed: {e}")
        return []


def fetch_race_results(user_id: str) -> list[dict]:
    """Fetch race/goal outcomes for anchoring predictions."""
    try:
        result = (
            supabase.table("goal_outcomes")
            .select("*")
            .eq("user_id", user_id)
            .not_.is_("actual_time_seconds", "null")
            .order("created_at", desc=True)
            .limit(10)
            .execute()
        )
        # Normalize to predictor's expected shape
        rows = []
        for r in (result.data or []):
            rows.append({
                "race_date": r.get("created_at", ""),
                "distance_type": r.get("race_distance", ""),
                "finish_time_seconds": r.get("actual_time_seconds", 0),
            })
        return rows
    except APIError as e:
        log.warning(f"goal_outcomes query failed: {e}")
        return []


def fetch_fitness_snapshots(user_id: str, limit: int = 20) -> list[dict]:
    """Fetch recent fitness snapshots for trend analysis."""
    try:
        result = (
            supabase.table("fitness_snapshots")
            .select("*")
            .eq("user_id", user_id)
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return result.data or []
    except APIError as e:
        log.warning(f"fitness_snapshots query failed: {e}")
        return []
