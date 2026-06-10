// Post Run Drip · iOS UI kit · Sign-in screen

const SignInScreen = ({ onSignIn }) => {
  const [email, setEmail] = React.useState("");
  const [password, setPassword] = React.useState("");
  const [loading, setLoading] = React.useState(false);

  const submit = () => {
    if (!email || !password) return;
    setLoading(true);
    setTimeout(() => { setLoading(false); onSignIn && onSignIn(); }, 600);
  };

  return (
    <div className="page">
      <div className="signin-shell">
        <div className="signin-logo">
          <img src="../../assets/PRD-Logo-On-Black.png" alt="post run drip" />
        </div>

        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6 }}>
          <h1 className="signin-title">Welcome back.</h1>
          <p className="signin-sub" style={{ marginTop: 6 }}>— a quieter log for serious runners. —</p>
        </div>

        <div className="signin-form">
          <input
            className="field"
            placeholder="Email"
            value={email}
            onChange={e => setEmail(e.target.value)}
            type="email"
            autoComplete="email"
          />
          <input
            className="field"
            placeholder="Password"
            value={password}
            onChange={e => setPassword(e.target.value)}
            type="password"
            autoComplete="current-password"
          />
          <button
            className="btn btn--primary"
            onClick={submit}
            disabled={!email || !password || loading}
            style={{ opacity: (!email || !password || loading) ? 0.5 : 1 }}>
            {loading ? "Signing in…" : "Sign in"}
          </button>
          <div className="apple-btn">
            <span style={{ fontSize: 18, lineHeight: 1 }}></span>
            <span>Sign in with Apple</span>
          </div>
          <div style={{ textAlign: "center", marginTop: 4 }}>
            <a className="link" style={{ fontSize: 12, color: "var(--ink-2)", borderColor: "var(--rule)" }}>Create account</a>
          </div>
        </div>
      </div>
    </div>
  );
};

window.SignInScreen = SignInScreen;
