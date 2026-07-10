import assert from "node:assert/strict";
import test from "node:test";
import { allowedTransition, type ExperimentStatus } from "../convex/productLoopRules.js";

test("a demo experiment can only progress from proposed to active and active to a terminal state", () => {
  const valid: Array<[ExperimentStatus, ExperimentStatus]> = [
    ["proposed", "active"],
    ["proposed", "cancelled"],
    ["active", "completed"],
    ["active", "cancelled"],
  ];
  for (const [from, to] of valid) assert.equal(allowedTransition(from, to), true);

  const invalid: Array<[ExperimentStatus, ExperimentStatus]> = [
    ["proposed", "completed"],
    ["active", "proposed"],
    ["completed", "active"],
    ["cancelled", "active"],
  ];
  for (const [from, to] of invalid) assert.equal(allowedTransition(from, to), false);
});
