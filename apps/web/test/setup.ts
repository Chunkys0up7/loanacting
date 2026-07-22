// Vitest setup file (referenced by vite.config.ts's test.setupFiles).
// No global test-library matchers are wired here — plan.md's own
// dependency list (specs/001-loan-actor-foundation/plan.md) doesn't
// name @testing-library/*, so component tests render via
// react-dom/client directly (see test/App.test.tsx).

// react-dom/client rendering wrapped in act() (React's own recommended
// direct-DOM-testing pattern without a testing-library) needs this flag,
// normally set by testing-library's own setup — since that's not in use
// here, set it directly.
declare global {
  var IS_REACT_ACT_ENVIRONMENT: boolean;
}

globalThis.IS_REACT_ACT_ENVIRONMENT = true;

export {};
