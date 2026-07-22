import type { LoanState } from "../types";

export interface StateCardProps {
  state: LoanState | null;
}

/** FT-032 — renders the loan's current status/version/goals/heartbeat. */
export function StateCard({ state }: StateCardProps) {
  if (!state) {
    return (
      <section aria-label="Loan state">
        <p>Loading state…</p>
      </section>
    );
  }

  return (
    <section aria-label="Loan state">
      <h2>Loan {state.loan_id}</h2>
      <dl>
        <dt>Status</dt>
        <dd>{state.status}</dd>
        <dt>Version</dt>
        <dd>{state.version}</dd>
        <dt>Last heartbeat</dt>
        <dd>{state.last_heartbeat_at ?? "never"}</dd>
      </dl>
      <h3>Goals</h3>
      {state.goals.length === 0 ? (
        <p>No goals yet.</p>
      ) : (
        <ul>
          {state.goals.map((goal) => (
            <li key={goal.goal_id}>
              {goal.description} — <strong>{goal.status}</strong>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
