import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const http = readFileSync(new URL("../convex/http.ts", import.meta.url), "utf8");
const state = readFileSync(new URL("../NoomApp/NoomApp/DashboardState.swift", import.meta.url), "utf8");

test("demo persistence is installation-scoped, catalog-backed, and never uploads health or app credentials", () => {
  assert.match(http, /x-noom-demo-install-id/);
  assert.match(http, /function demoScoped/);
  assert.match(http, /demoCatalog/);
  assert.doesNotMatch(http, /ctx\.auth|getUserIdentity|Authorization|overnight-signals|restingHeartRate|nocturnalHrv|sleepScore|Body Status|note|timezone|consentVersion/);
  assert.match(http, /validIdempotencyKey/);
  assert.match(http, /onlyKeys/);
  assert.match(state, /DemoInstallIdentity/);
  assert.match(state, /isServerCompatible/);
  assert.doesNotMatch(state, /generateTemporaryAuthToken|syncOvernightStatus|Authorization|BodyStatusScore|body-status/);
});
