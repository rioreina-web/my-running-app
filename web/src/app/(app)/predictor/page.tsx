"use client";

import { useState } from "react";
import { createBrowserClient } from "@supabase/ssr";
import { Card } from "@/components/ui/card";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import { DripButton } from "@/components/ui/drip-button";

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
              session?.access_token ||
              process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
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
    <div className="mx-auto max-w-3xl space-y-8">
      <div>
        <h1 className="font-display text-3xl text-text-primary">
          Fitness Predictor
        </h1>
        <p className="mt-1 font-body text-sm text-text-secondary">
          AI-powered race time predictions based on your recent training data.
        </p>
      </div>

      {!predictions && !loading && (
        <DripButton onClick={fetchPredictions}>
          Generate Predictions
        </DripButton>
      )}

      {loading && (
        <Card>
          <div className="py-8 text-center">
            <div className="animate-pulse font-body text-sm italic text-text-tertiary">
              Analyzing your training data...
            </div>
          </div>
        </Card>
      )}

      {error && (
        <Card accent>
          <p className="text-sm text-mood-injured">{error}</p>
        </Card>
      )}

      {predictions && (
        <div className="space-y-4">
          {predictions.map((pred, i) => (
            <Card key={i}>
              <div className="flex items-center justify-between">
                <h3 className="font-display text-lg text-text-primary">
                  {pred.race_distance}
                </h3>
                <span className="font-mono text-xs text-text-tertiary">
                  {pred.confidence} confidence
                </span>
              </div>
              <div className="mt-2 font-mono text-3xl font-semibold text-coral">
                {pred.predicted_time}
              </div>
              {pred.notes && (
                <p className="mt-2 text-sm text-text-secondary">
                  {pred.notes}
                </p>
              )}
            </Card>
          ))}

          <EditorialDivider />

          <button
            onClick={fetchPredictions}
            className="font-body text-xs italic text-text-tertiary hover:text-coral transition-colors"
          >
            Refresh predictions
          </button>
        </div>
      )}
    </div>
  );
}
