// Plan Builder · shared sub-components for the 3 directions

// ====================================================================
// Sidebar — the existing PRD coach portal sidebar, on-brand
// ====================================================================

const NAV_PRIMARY = [
  { label: "Dashboard" },
  { label: "Training Log" },
  { label: "Coach" },
  { label: "Plan" },
];
const NAV_COACH = [
  { label: "Coach Portal", active: true },
  { label: "Goals" },
  { label: "Analysis" },
  { label: "Injuries" },
  { label: "Fitness Predictor" },
  { label: "Pace Chart" },
  { label: "Content Library" },
];
const NAV_BOTTOM = [
  { label: "Export" },
  { label: "Settings" },
];

const Sidebar = () => (
  <aside className="sidebar">
    <div className="logo">
      <img src="../../../assets/PRD-Logo-On-Black.png" style={{ width: "100%", borderRadius: 6 }} alt="PRD" />
    </div>

    <div className="nav-section">
      <span className="sec-label">Athlete</span>
      {NAV_PRIMARY.map(n => (
        <a key={n.label} className="nav-item">{n.label}</a>
      ))}
    </div>

    <div className="nav-section">
      <span className="sec-label">Coach tools</span>
      {NAV_COACH.map(n => (
        <a key={n.label} className={"nav-item" + (n.active ? " is-active" : "")}>{n.label}</a>
      ))}
    </div>

    <div className="nav-spacer"></div>

    <div className="nav-section" style={{ marginBottom: 0 }}>
      {NAV_BOTTOM.map(n => (
        <a key={n.label} className="nav-item">{n.label}</a>
      ))}
    </div>
  </aside>
);

// ====================================================================
// Plan data — the screenshot's plan
// ====================================================================
const PLAN = {
  name: "2 week test",
  type: "adaptive",   // fixed | adaptive
  distance: "half_marathon",
  weeks: 2,
  paceRef: {
    source: "from 1:07:30 half marathon",
    paces: [
      { z: "MP",   v: "5:23" },
      { z: "HM",   v: "5:09" },
      { z: "5K",   v: "4:45" },
      { z: "Easy", v: "6:44–7:42" },
    ],
  },
  week: {
    weekNumber: 1,
    workouts: 7,
    quality: 24.5,
    rangeMin: 50,
    rangeMax: 70,
    days: [
      { name: "Mon", type: "auto",    title: "Auto · easy run (per athlete)" },
      { name: "Tue", type: "tempo",   title: "3@LT + 2@LT-2%", miles: 9.5 },
      { name: "Wed", type: "auto",    title: "Auto · easy run (per athlete)" },
      { name: "Thu", type: "auto",    title: "Auto · easy run (per athlete)" },
      { name: "Fri", type: "auto",    title: "Auto · easy run (per athlete)" },
      { name: "Sat", type: "long_run", title: "15m long run", miles: 15.0 },
      { name: "Sun", type: "auto",    title: "Auto · easy run (per athlete)" },
    ],
  },
};

window.Sidebar = Sidebar;
window.PLAN = PLAN;
