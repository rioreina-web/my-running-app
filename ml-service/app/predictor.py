"""
Fitness prediction engine.

Phase 1: Heuristic predictions from workout_features (mirrors Swift logic).
Phase 2: Trained ML model loaded from disk, falls back to heuristic.

The model predicts estimated 10K pace (seconds/mile) from training features.
All other race times are derived from 10K pace via performance ratios.
"""

import os
import math
from datetime import datetime, timedelta

import numpy as np
import joblib

from app.config import MODEL_DIR

# Performance ratios (10K = 1.0 baseline)
# Maps distance to (ratio, distance_in_miles) for time conversion
RACE_RATIOS = {
    "mile": (0.139583, 1.0),
    "5k": (0.481250, 3.10686),
    "10k": (1.0, 6.21371),
    "half": (2.204167, 13.1094),
    "marathon": (4.615625, 26.2188),
}


def equivalent_time(from_10k_seconds: int, distance: str) -> int:
    """Convert 10K time to equivalent race time using performance ratios."""
    ratio = RACE_RATIOS.get(distance, (1.0, 6.21371))[0]
    return round(from_10k_seconds * ratio)


def format_time(total_seconds: int) -> str:
    """Format seconds as H:MM:SS or M:SS."""
    hours = total_seconds // 3600
    minutes = (total_seconds % 3600) // 60
    seconds = total_seconds % 60
    if hours > 0:
        return f"{hours}:{minutes:02d}:{seconds:02d}"
    return f"{minutes}:{seconds:02d}"


def format_pace(seconds_per_mile: float) -> str:
    """Format pace as M:SS/mi."""
    minutes = int(seconds_per_mile // 60)
    secs = int(seconds_per_mile % 60)
    return f"{minutes}:{secs:02d}"


class FitnessPredictor:
    def __init__(self):
        self.model = None
        self.feature_columns = None
        self._try_load_model()

    def _try_load_model(self):
        """Attempt to load a trained model from disk."""
        model_path = os.path.join(MODEL_DIR, "fitness_model.joblib")
        columns_path = os.path.join(MODEL_DIR, "feature_columns.joblib")
        if os.path.exists(model_path) and os.path.exists(columns_path):
            self.model = joblib.load(model_path)
            self.feature_columns = joblib.load(columns_path)

    def predict(self, features: list[dict], race_results: list[dict]) -> dict:
        """
        Generate fitness prediction from workout features.
        Returns predicted race times, confidence, and training summary.
        """
        if not features:
            return {"error": "No workout data available", "predictions": []}

        # Try ML model first, fall back to heuristic
        if self.model is not None and self.feature_columns is not None:
            return self._predict_ml(features, race_results)
        return self._predict_heuristic(features, race_results)

    def _predict_heuristic(self, features: list[dict], race_results: list[dict]) -> dict:
        """
        Heuristic prediction mirroring the Swift FitnessPredictorService logic:
        1. Find best anchor (race result or recent snapshot)
        2. Apply time decay modulated by training stimulus
        3. Derive race times from estimated 10K pace
        """
        estimated_10k_pace = 0.0  # seconds per mile
        data_source = "default"
        confidence = "Low"

        # --- Step 1: Find anchor ---
        anchor_pace = None
        anchor_weeks_ago = 0.0

        # Check race results for anchor
        if race_results:
            best_race = race_results[0]  # most recent
            race_date_str = best_race.get("race_date", "")
            race_time_seconds = best_race.get("finish_time_seconds", 0)
            race_distance = best_race.get("distance_type", "").lower()

            if race_time_seconds > 0 and race_distance in RACE_RATIOS:
                ratio, miles = RACE_RATIOS[race_distance]
                # Convert race time to equivalent 10K time, then to pace
                ten_k_time = race_time_seconds / ratio if ratio > 0 else race_time_seconds
                anchor_pace = ten_k_time / 6.21371  # pace per mile

                if race_date_str:
                    try:
                        race_date = datetime.fromisoformat(race_date_str.replace("Z", "+00:00"))
                        anchor_weeks_ago = (datetime.now(race_date.tzinfo) - race_date).days / 7.0
                    except (ValueError, TypeError):
                        anchor_weeks_ago = 4.0

                data_source = f"race ({race_distance})"
                confidence = "High" if anchor_weeks_ago < 8 else "Medium"

        # --- Step 2: Apply decay modulated by training ---
        recent = features[-14:] if len(features) >= 14 else features  # last 2 weeks
        weekly_miles = sum(f.get("total_distance_miles", 0) or 0 for f in recent) / max(len(recent) / 7, 1)
        hard_minutes_weekly = sum(f.get("hard_effort_minutes", 0) or 0 for f in recent) / max(len(recent) / 7, 1)

        if anchor_pace:
            # Base decay: 0.3%/week, reduced by training quality
            base_decay = 0.003
            volume_factor = min(weekly_miles / 30.0, 1.0)  # 30 mpw = full mitigation
            quality_factor = min(hard_minutes_weekly / 20.0, 1.0)  # 20 hard min/wk = full
            effective_decay = base_decay * (1.0 - 0.4 * volume_factor - 0.3 * quality_factor)

            # Can go negative (improving) with strong training
            if volume_factor > 0.7 and quality_factor > 0.5:
                effective_decay = max(effective_decay, -0.002)

            decay_factor = 1.0 + (anchor_weeks_ago * effective_decay)
            estimated_10k_pace = anchor_pace * decay_factor
        else:
            # No race anchor — estimate from training paces
            paced_workouts = [f for f in features if (f.get("avg_pace_seconds") or 0) > 0]
            if paced_workouts:
                # Use fastest sustained workout as rough 10K estimate
                fastest = min(paced_workouts, key=lambda f: f["avg_pace_seconds"])
                estimated_10k_pace = fastest["avg_pace_seconds"] * 0.95
                data_source = "training pace"
                confidence = "Low"
            else:
                estimated_10k_pace = 480  # 8:00/mi fallback
                data_source = "default"
                confidence = "Low"

        # --- Step 3: Derive race predictions ---
        ten_k_seconds = round(estimated_10k_pace * 6.21371)

        predictions = []
        for distance, (ratio, miles) in RACE_RATIOS.items():
            time_seconds = equivalent_time(ten_k_seconds, distance)
            pace_seconds = time_seconds / miles if miles > 0 else 0
            predictions.append({
                "distance": distance,
                "time_seconds": time_seconds,
                "time_formatted": format_time(time_seconds),
                "pace_per_mile": format_pace(pace_seconds),
            })

        # --- Training summary ---
        all_miles = [f.get("total_distance_miles", 0) or 0 for f in features]
        all_hard = [f.get("hard_effort_minutes", 0) or 0 for f in features]
        latest = features[-1] if features else {}

        return {
            "predictions": predictions,
            "estimated_10k_pace_seconds": round(estimated_10k_pace, 1),
            "estimated_10k_pace": format_pace(estimated_10k_pace),
            "confidence": confidence,
            "data_source": data_source,
            "method": "heuristic",
            "training_summary": {
                "workout_count": len(features),
                "weekly_miles": round(weekly_miles, 1),
                "weekly_hard_minutes": round(hard_minutes_weekly, 1),
                "latest_acwr": latest.get("acwr"),
                "latest_monotony": latest.get("monotony_7d"),
                "latest_strain": latest.get("strain_7d"),
            },
        }

    def _predict_ml(self, features: list[dict], race_results: list[dict]) -> dict:
        """ML-based prediction using trained model."""
        import pandas as pd

        # Build feature vector from most recent workout features
        recent = features[-28:] if len(features) >= 28 else features

        # Aggregate features into a single row
        agg = {
            "avg_weekly_miles": np.mean([f.get("rolling_7d_miles", 0) or 0 for f in recent]),
            "avg_hard_minutes": np.mean([f.get("rolling_7d_hard_minutes", 0) or 0 for f in recent]),
            "avg_intensity_score": np.mean([f.get("intensity_score", 1) or 1 for f in recent]),
            "avg_pace_seconds": np.mean([f.get("avg_pace_seconds", 0) or 0 for f in [r for r in recent if (r.get("avg_pace_seconds") or 0) > 0]] or [480]),
            "peak_pace_seconds": min([f.get("peak_pace_seconds", 999) or 999 for f in recent]),
            "avg_pace_variance": np.mean([f.get("pace_variance", 0) or 0 for f in recent]),
            "latest_acwr": recent[-1].get("acwr", 1.0) or 1.0,
            "latest_monotony": recent[-1].get("monotony_7d", 0) or 0,
            "latest_strain": recent[-1].get("strain_7d", 0) or 0,
            "workout_count": len(recent),
            "avg_recovery_hours": np.mean([f.get("hours_since_last_workout", 24) or 24 for f in recent]),
            "hard_workout_ratio": sum(1 for f in recent if (f.get("hard_effort_minutes") or 0) > 5) / max(len(recent), 1),
        }

        # Add HR features if available
        hr_workouts = [f for f in recent if f.get("has_hr_data")]
        if hr_workouts:
            agg["avg_heart_rate"] = np.mean([f.get("avg_heart_rate", 0) or 0 for f in hr_workouts])
            agg["avg_hr_efficiency"] = np.mean([f.get("hr_pace_efficiency", 0) or 0 for f in hr_workouts if (f.get("hr_pace_efficiency") or 0) > 0])
        else:
            agg["avg_heart_rate"] = 0
            agg["avg_hr_efficiency"] = 0

        # Create DataFrame with expected columns
        df = pd.DataFrame([agg])
        for col in self.feature_columns:
            if col not in df.columns:
                df[col] = 0
        df = df[self.feature_columns]

        # Predict 10K pace
        predicted_pace = self.model.predict(df)[0]

        ten_k_seconds = round(predicted_pace * 6.21371)
        predictions = []
        for distance, (ratio, miles) in RACE_RATIOS.items():
            time_seconds = equivalent_time(ten_k_seconds, distance)
            pace_seconds = time_seconds / miles if miles > 0 else 0
            predictions.append({
                "distance": distance,
                "time_seconds": time_seconds,
                "time_formatted": format_time(time_seconds),
                "pace_per_mile": format_pace(pace_seconds),
            })

        latest = features[-1] if features else {}
        recent_14 = features[-14:] if len(features) >= 14 else features
        weekly_miles = sum(f.get("total_distance_miles", 0) or 0 for f in recent_14) / max(len(recent_14) / 7, 1)
        hard_minutes_weekly = sum(f.get("hard_effort_minutes", 0) or 0 for f in recent_14) / max(len(recent_14) / 7, 1)

        return {
            "predictions": predictions,
            "estimated_10k_pace_seconds": round(predicted_pace, 1),
            "estimated_10k_pace": format_pace(predicted_pace),
            "confidence": "High" if len(features) >= 30 else "Medium" if len(features) >= 15 else "Low",
            "data_source": "ml_model",
            "method": "xgboost",
            "training_summary": {
                "workout_count": len(features),
                "weekly_miles": round(weekly_miles, 1),
                "weekly_hard_minutes": round(hard_minutes_weekly, 1),
                "latest_acwr": latest.get("acwr"),
                "latest_monotony": latest.get("monotony_7d"),
                "latest_strain": latest.get("strain_7d"),
            },
        }


# Singleton
predictor = FitnessPredictor()
