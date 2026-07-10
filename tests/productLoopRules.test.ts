import assert from "node:assert/strict";
import test from "node:test";

import {
  allowedTransition,
  normalizeProgressSignal,
  type ExperimentStatus,
} from "../convex/productLoopRules.js";

test("an experiment can only progress from proposed to active and active to a terminal state", () => {
  const transitions: Array<[ExperimentStatus, ExperimentStatus, boolean]> = [
    ["proposed", "active", true],
    ["proposed", "cancelled", true],
    ["proposed", "completed", false],
    ["active", "completed", true],
    ["active", "cancelled", true],
    ["completed", "active", false],
    ["cancelled", "active", false],
  ];

  for (const [from, to, expected] of transitions) {
    assert.equal(allowedTransition(from, to), expected, `${from} -> ${to}`);
  }
});

test("progress accepts processed overnight signals and rejects raw PPG and invalid coverage", () => {
  assert.deepEqual(
    normalizeProgressSignal({
      signalType: "sleep_score",
      value: 82,
      unit: "score",
      coverage: 0.92,
    }),
    { signalType: "sleep_score", value: 82, unit: "score", coverage: 0.92 },
  );

  assert.throws(
    () => normalizeProgressSignal({ signalType: "raw_ppg", value: 12, unit: "hz", coverage: 1 }),
    /Unsupported progress signal/,
  );
  assert.throws(
    () => normalizeProgressSignal({ signalType: "hrv", value: 42, unit: "ms", coverage: 1.1 }),
    /coverage/,
  );
});
