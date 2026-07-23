import type { DiaryEntry } from "../types";

export interface DiaryFeedProps {
  entries: DiaryEntry[];
}

/** FT-032 — a live feed of diary entries, newest last (arrival order). */
export function DiaryFeed({ entries }: DiaryFeedProps) {
  if (entries.length === 0) {
    return (
      <section aria-label="Diary feed">
        <p>No diary entries yet.</p>
      </section>
    );
  }

  return (
    <section aria-label="Diary feed">
      <ul>
        {entries.map((entry) => (
          <li key={`${entry.loan_id}-${entry.sequence}`}>
            #{entry.sequence} <strong>{entry.type}</strong> by {entry.actor} at {entry.timestamp}
          </li>
        ))}
      </ul>
    </section>
  );
}
