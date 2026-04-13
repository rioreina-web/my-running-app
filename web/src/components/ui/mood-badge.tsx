const MOOD_COLORS: Record<string, string> = {
  energized: "text-mood-energized bg-mood-energized/12",
  positive: "text-mood-positive bg-mood-positive/12",
  neutral: "text-mood-neutral bg-mood-neutral/12",
  tired: "text-mood-tired bg-mood-tired/12",
  struggling: "text-mood-struggling bg-mood-struggling/12",
  injured: "text-mood-injured bg-mood-injured/12",
};

export function MoodBadge({ mood }: { mood: string }) {
  const key = mood.toLowerCase();
  const colors = MOOD_COLORS[key] || MOOD_COLORS.neutral;

  return (
    <span className={`inline-flex items-center gap-1 px-2 py-1 rounded-full text-[10px] font-semibold ${colors}`}>
      {mood.charAt(0).toUpperCase() + mood.slice(1)}
    </span>
  );
}
