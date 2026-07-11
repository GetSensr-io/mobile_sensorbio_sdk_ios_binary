import { httpRouter } from "convex/server";
import { httpAction } from "./_generated/server";
import { internal } from "./_generated/api";

const http = httpRouter();
const jsonHeaders = { "content-type": "application/json", "cache-control": "no-store" };
const demoInstallHeader = "x-noom-demo-install-id";
const demoInstallIdPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function response(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

function failure(status: number, message: string): Response {
  return response({ error: message }, status);
}

async function body(request: Request): Promise<Record<string, unknown>> {
  const value: unknown = await request.json();
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("Invalid JSON body");
  return value as Record<string, unknown>;
}

function onlyKeys(data: Record<string, unknown>, allowed: readonly string[]) {
  if (Object.keys(data).some((key) => !allowed.includes(key))) {
    throw new Error("Unexpected demo field");
  }
}

function id(value: unknown): string {
  if (typeof value !== "string" || !value.trim()) throw new Error("Missing identifier");
  return value;
}

// The demo API accepts only a fixed catalog identifier. It must not accept
// titles, reasons, dates, or any state derived from a person's band data.
const demoCatalogIds = new Set(["prelog-lunch-v1"]);

function demoCatalogId(data: Record<string, unknown>): "prelog-lunch-v1" {
  const key = id(data.demoCatalogId);
  if (!demoCatalogIds.has(key)) throw new Error("Unknown demo catalog entry");
  return "prelog-lunch-v1";
}

function validIdempotencyKey(value: unknown): string {
  const key = id(value);
  if (!demoInstallIdPattern.test(key)) throw new Error("Invalid idempotency key");
  return key.toLowerCase();
}

function demoInstallId(request: Request): string {
  const value = request.headers.get(demoInstallHeader)?.trim();
  if (!value || !demoInstallIdPattern.test(value)) throw new Error("Invalid demo installation");
  return value.toLowerCase();
}

// This endpoint is intentionally for fictional demo state only. The opaque
// per-install identifier is not an account identity and must never scope health data.
async function demoScoped(
  ctx: any,
  request: Request,
  handler: (demoInstallId: string, data: Record<string, unknown>) => Promise<unknown>,
): Promise<Response> {
  try {
    const installId = demoInstallId(request);
    const data = request.method === "GET" ? {} : await body(request);
    return response(await handler(installId, data));
  } catch {
    return failure(400, "Invalid demo product-loop request");
  }
}

http.route({
  path: "/health",
  method: "GET",
  handler: httpAction(async () => response({ service: "sensor-bio-product-loop-demo", schemaVersion: 2 })),
});

http.route({
  path: "/demo/v1/current",
  method: "GET",
  handler: httpAction((ctx, request) => demoScoped(ctx, request, (demoInstallId) => ctx.runQuery(internal.productLoop.getCurrent, { demoInstallId }))),
});

http.route({
  path: "/demo/v1/proposals",
  method: "POST",
  handler: httpAction((ctx, request) => demoScoped(ctx, request, (demoInstallId, data) => {
    onlyKeys(data, ["demoCatalogId"]);
    return ctx.runMutation(internal.productLoop.createProposal, {
      demoInstallId,
      demoCatalogId: demoCatalogId(data),
    });
  })),
});

for (const [path, action] of [["/demo/v1/experiments/accept", "accept"], ["/demo/v1/experiments/complete", "complete"], ["/demo/v1/experiments/cancel", "cancel"]] as const) {
  http.route({
    path,
    method: "POST",
    handler: httpAction((ctx, request) => demoScoped(ctx, request, (demoInstallId, data) => {
      onlyKeys(data, ["experimentId", "idempotencyKey"]);
      return ctx.runMutation(internal.productLoop[action], {
        demoInstallId,
        experimentId: id(data.experimentId) as never,
        idempotencyKey: validIdempotencyKey(data.idempotencyKey),
      });
    })),
  });
}

http.route({
  path: "/demo/v1/preferences",
  method: "PUT",
  handler: httpAction((ctx, request) => demoScoped(ctx, request, (demoInstallId, data) => {
    onlyKeys(data, ["dailyCheckInEnabled", "experimentReminderEnabled"]);
    return ctx.runMutation(internal.productLoop.savePreferences, {
      demoInstallId,
      dailyCheckInEnabled: data.dailyCheckInEnabled === true,
      experimentReminderEnabled: data.experimentReminderEnabled === true,
    });
  })),
});

export default http;
