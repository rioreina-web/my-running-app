"""
Model training script.

Run when you have enough data (6+ months of workouts, 2+ race results).
Trains an XGBoost model to predict 10K pace from workout features.

Usage:
    python train.py

The model is saved to models/ and automatically loaded by the API on restart.
"""

import os
import sys

import numpy as np
import pandas as pd
import joblib
from xgboost import XGBRegressor
from sklearn.model_selection import TimeSeriesSplit
from sklearn.metrics import mean_absolute_error

from app.config import MODEL_DIR
from app.db import supabase


def fetch_training_data():
    """Fetch workout features paired with fitness snapshot targets."""
    # Get all workout features
    features_result = supabase.table("workout_features").select("*").order("workout_date").execute()
    features = features_result.data or []

    # Get all fitness snapshots (our training labels)
    snapshots_result = supabase.table("fitness_snapshots").select("*").order("created_at").execute()
    snapshots = snapshots_result.data or []

    return features, snapshots


def build_training_set(features: list[dict], snapshots: list[dict]) -> tuple[pd.DataFrame, pd.Series]:
    """
    Build X (features) and y (target) for training.

    For each fitness snapshot, compute aggregate features from the
    workout data in the preceding 28 days. The target is the snapshot's
    estimated_10k_pace_seconds.
    """
    if not snapshots:
        print("No fitness snapshots found. Run the fitness predictor in the app first.")
        sys.exit(1)

    rows = []
    targets = []

    for snap in snapshots:
        snap_date = snap.get("created_at", "")
        target_pace = snap.get("estimated_10k_pace_seconds")
        if not target_pace or target_pace <= 0:
            continue

        # Find workouts in the 28 days before this snapshot
        from datetime import datetime, timedelta
        try:
            snap_dt = datetime.fromisoformat(snap_date.replace("Z", "+00:00"))
        except (ValueError, TypeError):
            continue

        cutoff = (snap_dt - timedelta(days=28)).isoformat()
        recent = [
            f for f in features
            if f.get("workout_date", "") >= cutoff and f.get("workout_date", "") <= snap_date
        ]

        if len(recent) < 3:
            continue

        # Aggregate features
        row = {
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

        # HR features
        hr_workouts = [f for f in recent if f.get("has_hr_data")]
        if hr_workouts:
            row["avg_heart_rate"] = np.mean([f.get("avg_heart_rate", 0) or 0 for f in hr_workouts])
            row["avg_hr_efficiency"] = np.mean([f.get("hr_pace_efficiency", 0) or 0 for f in hr_workouts if (f.get("hr_pace_efficiency") or 0) > 0])
        else:
            row["avg_heart_rate"] = 0
            row["avg_hr_efficiency"] = 0

        rows.append(row)
        targets.append(target_pace)

    if not rows:
        print("Not enough paired data (workouts + snapshots) to train.")
        print(f"  Workout features: {len(features)}")
        print(f"  Fitness snapshots: {len(snapshots)}")
        print("  Need at least 3 workouts before each snapshot.")
        sys.exit(1)

    X = pd.DataFrame(rows)
    y = pd.Series(targets, name="estimated_10k_pace_seconds")
    return X, y


def train_model(X: pd.DataFrame, y: pd.Series):
    """Train XGBoost with time-series cross-validation."""
    print(f"Training on {len(X)} samples with {len(X.columns)} features")
    print(f"Target range: {y.min():.0f} - {y.max():.0f} sec/mi")

    model = XGBRegressor(
        n_estimators=100,
        max_depth=4,
        learning_rate=0.1,
        subsample=0.8,
        colsample_bytree=0.8,
        random_state=42,
    )

    # Time-series cross-validation (don't leak future data)
    if len(X) >= 10:
        tscv = TimeSeriesSplit(n_splits=min(5, len(X) // 2))
        mae_scores = []
        for train_idx, val_idx in tscv.split(X):
            X_train, X_val = X.iloc[train_idx], X.iloc[val_idx]
            y_train, y_val = y.iloc[train_idx], y.iloc[val_idx]
            model.fit(X_train, y_train)
            preds = model.predict(X_val)
            mae = mean_absolute_error(y_val, preds)
            mae_scores.append(mae)
        print(f"Cross-validation MAE: {np.mean(mae_scores):.1f} sec/mi (+/- {np.std(mae_scores):.1f})")

    # Train final model on all data
    model.fit(X, y)

    # Feature importance
    importances = sorted(zip(X.columns, model.feature_importances_), key=lambda x: -x[1])
    print("\nFeature importance:")
    for name, imp in importances[:10]:
        print(f"  {name}: {imp:.3f}")

    return model


def save_model(model, feature_columns: list[str]):
    """Save model and feature columns to disk."""
    os.makedirs(MODEL_DIR, exist_ok=True)
    model_path = os.path.join(MODEL_DIR, "fitness_model.joblib")
    columns_path = os.path.join(MODEL_DIR, "feature_columns.joblib")

    joblib.dump(model, model_path)
    joblib.dump(feature_columns, columns_path)
    print(f"\nModel saved to {model_path}")
    print(f"Feature columns saved to {columns_path}")


if __name__ == "__main__":
    print("Fetching training data...")
    features, snapshots = fetch_training_data()
    print(f"  {len(features)} workout features, {len(snapshots)} fitness snapshots")

    print("Building training set...")
    X, y = build_training_set(features, snapshots)

    print("Training model...")
    model = train_model(X, y)

    print("Saving model...")
    save_model(model, list(X.columns))

    print("\nDone! Restart the API to use the new model.")
