// Post Run Drip · iOS UI kit · App orchestrator
// Renders an iOS frame with one of the screens inside,
// plus a tab bar at the bottom for navigation.

const App = () => {
  // "app" | "signin" | "onboarding"
  const [stage, setStage] = React.useState("app");
  const [tab, setTab] = React.useState("log");
  const [sheet, setSheet] = React.useState(null);
  const [sheetDay, setSheetDay] = React.useState(null);
  const [menuOpen, setMenuOpen] = React.useState(false);

  const openSheet = (kind) => { setMenuOpen(false); setSheet(kind); };
  // Menu selection — most ids open a sheet; Training Analysis jumps to the
  // Trends tab (that IS the analysis surface).
  const onMenuSelect = (id) => {
    if (id === "analysis") { setMenuOpen(false); setTab("trends"); }
    else openSheet(id);
  };
  const openDay = (day) => { setSheetDay(day); setSheet("day"); };

  // Sheets and tabs (only relevant in "app" stage)
  let body;
  if (sheet === "workout")        body = <WorkoutDetailScreen onClose={() => setSheet(null)} />;
  else if (sheet === "injuries")  body = <InjuriesScreen onClose={() => setSheet(null)} onAdd={() => setSheet("addInjury")} onOpenInjury={() => setSheet("injuryDetail")} />;
  else if (sheet === "day")       body = <DayDetailSheet day={sheetDay} onClose={() => setSheet(null)} onMarkComplete={() => setSheet(null)} />;
  else if (sheet === "picker")    body = <WorkoutPickerSheet onClose={() => setSheet(null)} onPick={() => setSheet(null)} />;
  else if (sheet === "manual")    body = <ManualWorkoutSheet onClose={() => setSheet(null)} />;
  else if (sheet === "history")   body = <HistoryDetailSheet onClose={() => setSheet(null)} onDelete={() => setSheet(null)} />;
  else if (sheet === "addInjury") body = <AddInjurySheet onClose={() => setSheet("injuries")} onSave={() => setSheet("injuries")} />;
  else if (sheet === "injuryDetail") body = <InjuryDetailSheet onClose={() => setSheet("injuries")} />;
  else if (sheet === "plan")      body = <TrainingPlanSheet onClose={() => setSheet(null)} onOpenDay={() => setSheet("day")} />;
  else if (sheet === "settings")  body = <SettingsScreen onClose={() => setSheet(null)} />;
  else if (sheet === "pace")      body = <PaceChartScreen onClose={() => setSheet(null)} />;
  else if (sheet === "predictor") body = <FitnessPredictorScreen onClose={() => setSheet(null)} />;
  else if (sheet === "library")   body = <ContentLibraryScreen onClose={() => setSheet(null)} />;
  else if (sheet === "profile")   body = <AthleteProfileScreen onClose={() => setSheet(null)} />;
  else if (sheet === "goals")     body = <GoalsScreen onClose={() => setSheet(null)} onAddGoal={() => {}} />;
  else if (sheet === "backup")    body = <BackupScreen onClose={() => setSheet(null)} />;
  else if (sheet === "export")    body = <ExportScreen onClose={() => setSheet(null)} />;
  else if (sheet === "about")     body = <SettingsScreen onClose={() => setSheet(null)} />;
  else if (sheet === "race")      body = <RacePlanScreen onClose={() => setSheet(null)} />;
  else if (sheet === "weeklyReview") body = <WeeklyReviewScreen onClose={() => setSheet(null)} />;
  else if (sheet === "history")    body = <RunsScreen onClose={() => setSheet(null)} onOpenWorkout={() => setSheet("workout")} onOpenEntry={() => setSheet("historyDetail")} onAddManual={() => setSheet("manual")} />;
  else if (sheet === "historyDetail") body = <HistoryDetailSheet onClose={() => setSheet("history")} onDelete={() => setSheet("history")} />;
  else if (tab === "log")         body = <LogScreen onOpenPicker={() => setSheet("picker")} onOpenEntry={() => setSheet("history")} />;
  else if (tab === "train")       body = <TrainingScreen onOpenDay={() => setSheet("day")} onOpenPlan={() => setTab("train")} onOpenWorkout={() => setSheet("workout")} onOpenRace={() => setSheet("race")} onOpenHistory={() => { setSheet(null); setTab("runs"); }} />;
  else if (tab === "trends")      body = <TrendsScreen onOpenWorkout={() => setSheet("workout")} onOpenInjuries={() => setSheet("injuries")} onOpenHistory={() => setSheet("history")} onOpenRace={() => setSheet("race")} />;
  else if (tab === "coach")       body = <CoachScreen onOpenReport={() => setSheet("weeklyReview")} />;
  else                            body = <RunsScreen onOpenWorkout={() => setSheet("workout")} onOpenEntry={() => setSheet("historyDetail")} onAddManual={() => setSheet("manual")} />;

  if (stage === "signin") {
    return (
      <IOSDevice width={390} height={844}>
        <div style={{ paddingTop: 62, height: "100%", boxSizing: "border-box", background: "#F5F3F0" }}>
          <SignInScreen
            onSignIn={() => setStage("app")}
            onCreateAccount={() => setStage("onboarding")}
          />
        </div>
      </IOSDevice>
    );
  }

  if (stage === "onboarding") {
    return (
      <IOSDevice width={390} height={844}>
        <div style={{ paddingTop: 62, height: "100%", boxSizing: "border-box", background: "#F5F3F0" }}>
          <OnboardingScreen
            onComplete={() => setStage("app")}
            onSkipAll={() => setStage("app")}
          />
        </div>
      </IOSDevice>
    );
  }

  return (
    <IOSDevice width={390} height={844}>
      <div style={{ paddingTop: 62, paddingBottom: 34, height: "100%", boxSizing: "border-box", display: "flex", flexDirection: "column", background: "#F5F3F0", position: "relative" }}>
        <div style={{ flex: 1, overflow: "hidden", position: "relative" }}>
          {body}
          {/* Hamburger — top-left of the screen body, available on every screen */}
          {!sheet && (
            <div
              onClick={() => setMenuOpen(true)}
              style={{
                position: "absolute", top: 8, left: 8, zIndex: 30,
                width: 28, height: 28, borderRadius: 999,
                display: "grid", placeItems: "center",
                cursor: "pointer",
                color: "var(--ink-2)",
                fontSize: 14, fontFamily: "var(--font-mono)",
              }}
              role="button"
              aria-label="Menu"
            >
              ☰
            </div>
          )}
          {/* Sidebar overlay */}
          {menuOpen && (
            <AppSidebar
              onClose={() => setMenuOpen(false)}
              onSelect={onMenuSelect}
              onSignOut={() => { setMenuOpen(false); setStage("signin"); }}
            />
          )}
        </div>
        {!sheet && <TabBar active={tab} onChange={setTab} />}
        {/* Dev affordance — relaunch sign-in / onboarding from the app */}
        <DevStageSwitcher onSelect={setStage} />
      </div>
    </IOSDevice>
  );
};

// Small floating control so reviewers can jump between sign-in, onboarding
// and the app without code edits. Lives outside the iOS frame visually.
const DevStageSwitcher = ({ onSelect }) => (
  <div style={{
    position: "absolute", top: 6, right: 6,
    display: "flex", gap: 6, zIndex: 50,
    fontFamily: "var(--font-mono)", fontSize: 9,
    letterSpacing: "0.12em", textTransform: "uppercase",
  }}>
    <span onClick={() => onSelect("signin")} style={{
      padding: "4px 8px", borderRadius: 999, cursor: "pointer",
      background: "rgba(255,255,255,0.06)", color: "rgba(255,255,255,0.55)",
      border: "1px solid rgba(255,255,255,0.10)",
    }}>SIGN-IN</span>
    <span onClick={() => onSelect("onboarding")} style={{
      padding: "4px 8px", borderRadius: 999, cursor: "pointer",
      background: "rgba(255,255,255,0.06)", color: "rgba(255,255,255,0.55)",
      border: "1px solid rgba(255,255,255,0.10)",
    }}>ONBOARDING</span>
  </div>
);

window.App = App;
// Mount
const root = ReactDOM.createRoot(document.getElementById("root"));
root.render(<App />);
