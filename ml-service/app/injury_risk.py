"""
Injury risk scoring from workout features.

Phase 1: Rule-based scoring from known risk factors.
Phase 2: Trained classifier from historical injury data.

Risk factors (evidence-based):
- ACWR > 1.5 or < 0.8 (acute:chronic workload ratio sweet spot is 0.8-1.3)
- High monotony (same load every day = overuse risk)
- High strain (volume * monotony)
- Volume spike > 10% week-over-week
- Insufficient recovery between hard sessions (< 48h)
- Mood declining (struggling/tired trend)
"""

from datetime import datetime


def compute_injury_risk(features: list[dict]) -> dict:
    """
    Score injury risk 0-100 from recent workout features.
    Returns risk score, contributing factors, and recommendations.
    """
    if not features:
        return {
            "risk_score": 0,
            "risk_level": "unknown",
            "factors": [],
            "recommendations": ["Not enough data to assess injury risk."],
        }

    recent = features[-14:] if len(features) >= 14 else features
    latest = features[-1]

    risk_points = 0
    max_points = 0
    factors = []

    # --- Factor 1: ACWR (25 points) ---
    max_points += 25
    acwr = latest.get("acwr")
    if acwr is not None:
        if acwr > 1.5:
            pts = 25
            factors.append({
                "factor": "ACWR dangerously high",
                "value": round(acwr, 2),
                "severity": "high",
                "detail": f"Your acute:chronic workload ratio is {acwr:.2f}. The danger zone is above 1.5. You've ramped up training too quickly.",
            })
        elif acwr > 1.3:
            pts = 15
            factors.append({
                "factor": "ACWR elevated",
                "value": round(acwr, 2),
                "severity": "medium",
                "detail": f"ACWR of {acwr:.2f} is in the caution zone (1.3-1.5). Monitor how your body responds.",
            })
        elif acwr < 0.8 and len(features) > 7:
            pts = 10
            factors.append({
                "factor": "ACWR low (detraining)",
                "value": round(acwr, 2),
                "severity": "low",
                "detail": f"ACWR of {acwr:.2f} suggests you're doing less than usual. Sudden ramp-up from here would be risky.",
            })
        else:
            pts = 0
        risk_points += pts

    # --- Factor 2: Monotony (20 points) ---
    max_points += 20
    monotony = latest.get("monotony_7d")
    if monotony is not None:
        if monotony > 2.0:
            pts = 20
            factors.append({
                "factor": "High training monotony",
                "value": round(monotony, 2),
                "severity": "high",
                "detail": "Your daily training load is very uniform. Vary your easy/hard days to reduce overuse risk.",
            })
        elif monotony > 1.5:
            pts = 10
            factors.append({
                "factor": "Moderate monotony",
                "value": round(monotony, 2),
                "severity": "medium",
                "detail": "Training is somewhat repetitive. Consider varying workout intensity across the week.",
            })
        else:
            pts = 0
        risk_points += pts

    # --- Factor 3: Volume spike (20 points) ---
    max_points += 20
    rolling_7d = latest.get("rolling_7d_miles", 0) or 0
    rolling_28d = latest.get("rolling_28d_miles", 0) or 0
    avg_weekly_28d = rolling_28d / 4 if rolling_28d > 0 else 0

    if avg_weekly_28d > 0:
        volume_change_pct = ((rolling_7d - avg_weekly_28d) / avg_weekly_28d) * 100
        if volume_change_pct > 20:
            pts = 20
            factors.append({
                "factor": "Sharp volume increase",
                "value": f"+{volume_change_pct:.0f}%",
                "severity": "high",
                "detail": f"This week's mileage is {volume_change_pct:.0f}% above your 4-week average. The 10% rule exists for a reason.",
            })
        elif volume_change_pct > 10:
            pts = 10
            factors.append({
                "factor": "Volume increasing",
                "value": f"+{volume_change_pct:.0f}%",
                "severity": "medium",
                "detail": f"Mileage up {volume_change_pct:.0f}% vs 4-week average. Manageable if you feel good.",
            })
        else:
            pts = 0
        risk_points += pts

    # --- Factor 4: Recovery between hard sessions (20 points) ---
    max_points += 20
    hard_workouts = [f for f in recent if (f.get("hard_effort_minutes") or 0) > 5]
    if len(hard_workouts) >= 2:
        recovery_gaps = []
        for i in range(1, len(hard_workouts)):
            hrs = hard_workouts[i].get("hours_since_last_hard")
            if hrs is not None:
                recovery_gaps.append(hrs)

        if recovery_gaps:
            min_recovery = min(recovery_gaps)
            avg_recovery = sum(recovery_gaps) / len(recovery_gaps)

            if min_recovery < 24:
                pts = 20
                factors.append({
                    "factor": "Back-to-back hard sessions",
                    "value": f"{min_recovery:.0f}h",
                    "severity": "high",
                    "detail": f"Only {min_recovery:.0f} hours between hard sessions. Aim for 48+ hours of recovery.",
                })
            elif avg_recovery < 48:
                pts = 10
                factors.append({
                    "factor": "Tight recovery windows",
                    "value": f"avg {avg_recovery:.0f}h",
                    "severity": "medium",
                    "detail": f"Averaging {avg_recovery:.0f} hours between hard sessions. More recovery would reduce injury risk.",
                })
            else:
                pts = 0
            risk_points += pts

    # --- Factor 5: Mood trend (15 points) ---
    max_points += 15
    mood_scores = {"energized": 5, "positive": 4, "neutral": 3, "tired": 2, "struggling": 1, "injured": 0}
    moods = [mood_scores.get(f.get("mood", ""), 3) for f in recent if f.get("mood")]
    if len(moods) >= 3:
        recent_mood_avg = sum(moods[-3:]) / 3
        if recent_mood_avg < 1.5:
            pts = 15
            factors.append({
                "factor": "Mood declining",
                "value": f"{recent_mood_avg:.1f}/5",
                "severity": "high",
                "detail": "Recent mood trend is struggling/injured. Your body is telling you something.",
            })
        elif recent_mood_avg < 2.5:
            pts = 8
            factors.append({
                "factor": "Mood below average",
                "value": f"{recent_mood_avg:.1f}/5",
                "severity": "medium",
                "detail": "You've been feeling more tired than usual. Consider an easy week.",
            })
        else:
            pts = 0
        risk_points += pts

    # --- Compute final score ---
    risk_score = round((risk_points / max(max_points, 1)) * 100) if max_points > 0 else 0

    if risk_score >= 70:
        risk_level = "high"
    elif risk_score >= 40:
        risk_level = "moderate"
    elif risk_score >= 15:
        risk_level = "low"
    else:
        risk_level = "minimal"

    # --- Recommendations ---
    recommendations = []
    if risk_level == "high":
        recommendations.append("Consider taking an easy day or rest day soon.")
        recommendations.append("Reduce volume by 20-30% this week.")
    elif risk_level == "moderate":
        recommendations.append("Monitor how you feel during your next few runs.")
        recommendations.append("Ensure at least 48 hours between hard sessions.")
    else:
        recommendations.append("Training load looks manageable. Keep it up.")

    return {
        "risk_score": risk_score,
        "risk_level": risk_level,
        "factors": factors,
        "recommendations": recommendations,
        "data_points": len(features),
    }
