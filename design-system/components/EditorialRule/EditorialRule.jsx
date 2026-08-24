// Post Run Drip · EditorialRule — line · dot · line section break.
export function EditorialRule({ style }) {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: "var(--space-2)", ...style }}>
      <span style={{ flex: 1, height: 1, background: "var(--rule)" }} />
      <span style={{ width: 3, height: 3, borderRadius: 999, background: "var(--rule)" }} />
      <span style={{ flex: 1, height: 1, background: "var(--rule)" }} />
    </div>
  );
}
