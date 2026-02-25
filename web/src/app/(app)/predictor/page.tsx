"use client";

import { useState } from "react";
import { createBrowserClient } from "@supabase/ssr";

interface Prediction {
  race_distance: string;
  predicted_time: string;
  confidence: string;
  notes: string;
}

export default function PredictorPage() {
  const [predictions, setPredictions] = useState<Prediction[] | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const supabase = createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  async function fetchPredictions() {
    setLoading(true);
    setError(null);

    try {
      const {
        data: { session },
      } = await supabase.auth.getSession();

      const res = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/fitness-predictor`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${
              session?.access_token || process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
            }`,
          },
          body: JSON.stringify({}),
        }
      );

      const data = await res.json();
      if (data.predictions) {
        setPredictions(data.predictions);
      } else if (data.error) {
        setError(data.error);
      }
    } catch {
      setError("Couldn't connect to the predictor. Try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <h1 className="font-display text-3xl tracking-wider text-text-primary">
        FITNESS PREDICTOR
      </h1>

      <p className="text-sm text-text-secondary">
        Get AI-powered race time predictions based on your recent training data.
      </p>

      {!predictions && !loading && (
        <button
          onClick={fetchPredictions}
          className="rounded-xl bg-coral px-6 py-3 font-mono text-sm font-medium text-white transition-colors hover:bg-coral-light"
        >
          Generate Predictions
        </button>
      )}

      {loading && (
        <div className="rounded-xl border border-bg-elevated bg-bg-card p-8 text-center">
          <div className="animate-pulse font-mono text-sm text-text-tertiary">
            Analyzing your training data...
          </div>
        </div>
      )}

      {error && (
        <div className="rounded-xl border border-mood-injured/30 bg-bg-card p-4 text-sm text-mood-injured">
          {error}
        </div>
      )}

      {predictions && (
        <div className="space-y-4">
          {predictions.map((pred, i) => (
            <div
              key={i}
              className="rounded-xl border border-bg-elevated bg-bg-card p-5"
            >
              <div className="flex items-center justify-between">
                <h3 className="font-medium text-text-primary">
                  {pred.race_distance}
                </h3>
                <span className="font-mono text-xs text-text-tertiary">
                  {pred.confidence} confidence
                </span>
              </div>
              <div className="mt-2 font-mono text-3xl font-bold text-coral">
                {pred.predicted_time}
              </div>
              {pred.notes && (
                <p className="mt-2 text-sm text-text-secondary">
                  {pred.notes}
                </p>
              )}
            </div>
          ))}
          <button
            onClick={fetchPredictions}
            className="font-mono text-xs text-text-tertiary hover:text-coral"
          >
            Refresh predictions
          </button>
        </div>
      )}
    </div>
  );
}
