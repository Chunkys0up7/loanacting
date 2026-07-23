import { useState, type FormEvent } from "react";
import { LoanView } from "./pages/LoanView";

/** FT-032 — minimal spawn/open flow so LoanView is reachable; no router (none in plan.md's dependency list). */
function App() {
  const [loanIdInput, setLoanIdInput] = useState("");
  const [activeLoanId, setActiveLoanId] = useState<string | null>(null);
  const [spawning, setSpawning] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleOpenLoan(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSpawning(true);
    setError(null);

    try {
      const response = await fetch("/loans", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(loanIdInput ? { loan_id: loanIdInput } : {}),
      });

      const body = (await response.json()) as { loan_id?: string; error?: string };

      if (response.ok && body.loan_id) {
        setActiveLoanId(body.loan_id);
      } else {
        setError(body.error ?? `HTTP ${response.status}`);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : String(err));
    } finally {
      setSpawning(false);
    }
  }

  if (activeLoanId) {
    return <LoanView loanId={activeLoanId} />;
  }

  return (
    <main>
      <h1>Loan as Actor</h1>
      <form aria-label="Spawn or open a loan" onSubmit={handleOpenLoan}>
        <label htmlFor="loan-id-input">Loan ID (optional — leave blank to generate one)</label>
        <input id="loan-id-input" value={loanIdInput} onChange={(event) => setLoanIdInput(event.target.value)} />
        <button type="submit" disabled={spawning}>
          {spawning ? "Opening…" : "Open loan"}
        </button>
      </form>
      {error && <p role="alert">{error}</p>}
    </main>
  );
}

export default App;
