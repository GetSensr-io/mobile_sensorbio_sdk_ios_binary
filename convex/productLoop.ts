import { ConvexError, v } from "convex/values";
import { mutation, query, type MutationCtx } from "./_generated/server";
import type { Id } from "./_generated/dataModel";
import { allowedTransition, normalizeProgressSignal } from "./productLoopRules";

const now = () => Date.now();

function validateLocalDate(value: string) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new ConvexError("localDate must use YYYY-MM-DD");
  }
}

export const getCurrent = query({
  args: {},
  handler: async (ctx) => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity === null) throw new ConvexError("Unauthenticated");

    const [active, proposals, preferences, devices] = await Promise.all([
      ctx.db.query("experiments").withIndex("by_owner_status", (q) => q.eq("ownerId", identity.subject).eq("status", "active")).first(),
      ctx.db.query("experiments").withIndex("by_owner_status", (q) => q.eq("ownerId", identity.subject).eq("status", "proposed")).collect(),
      ctx.db.query("signalPreferences").withIndex("by_owner", (q) => q.eq("ownerId", identity.subject)).first(),
      ctx.db.query("pushDevices").withIndex("by_owner_token", (q) => q.eq("ownerId", identity.subject)).collect(),
    ]);

    return { active, proposals, preferences, registeredDeviceCount: devices.length };
  },
});

export const createProposal = mutation({
  args: {
    sourceInsightId: v.string(),
    experimentMethodId: v.optional(v.string()),
    title: v.string(),
    reason: v.string(),
    instructions: v.string(),
    expectedDurationDays: v.number(),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity === null) throw new ConvexError("Unauthenticated");
    if (!args.title.trim() || !args.reason.trim() || !args.instructions.trim()) {
      throw new ConvexError("Experiment title, reason, and instructions are required");
    }
    if (!Number.isInteger(args.expectedDurationDays) || args.expectedDurationDays < 1 || args.expectedDurationDays > 56) {
      throw new ConvexError("expectedDurationDays must be between 1 and 56");
    }

    const existing = await ctx.db
      .query("experiments")
      .withIndex("by_owner_source", (q) => q.eq("ownerId", identity.subject).eq("sourceInsightId", args.sourceInsightId))
      .first();
    if (existing) return existing;

    const timestamp = now();
    const id = await ctx.db.insert("experiments", {
      ownerId: identity.subject,
      sourceInsightId: args.sourceInsightId,
      experimentMethodId: args.experimentMethodId,
      title: args.title.trim(),
      reason: args.reason.trim(),
      instructions: args.instructions.trim(),
      expectedDurationDays: args.expectedDurationDays,
      status: "proposed",
      statusVersion: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    return await ctx.db.get(id);
  },
});

const transitionArgs = {
  experimentId: v.id("experiments"),
  idempotencyKey: v.string(),
  note: v.optional(v.string()),
};

async function transitionExperiment(
  ctx: MutationCtx,
  args: { experimentId: Id<"experiments">; idempotencyKey: string; note?: string },
  target: "active" | "completed" | "cancelled",
) {
  const identity = await ctx.auth.getUserIdentity();
  if (identity === null) throw new ConvexError("Unauthenticated");
  if (!args.idempotencyKey.trim()) throw new ConvexError("idempotencyKey is required");

  const previousEvent = await ctx.db
    .query("experimentEvents")
    .withIndex("by_owner_idempotency", (q) => q.eq("ownerId", identity.subject).eq("idempotencyKey", args.idempotencyKey))
    .first();
  if (previousEvent) return await ctx.db.get(previousEvent.experimentId);

  const experiment = await ctx.db.get(args.experimentId);
  if (!experiment || experiment.ownerId !== identity.subject) throw new ConvexError("Experiment not found");
  if (!allowedTransition(experiment.status, target)) {
    throw new ConvexError(`Invalid experiment transition: ${experiment.status} -> ${target}`);
  }
  if (target === "active") {
    const active = await ctx.db
      .query("experiments")
      .withIndex("by_owner_status", (q) => q.eq("ownerId", identity.subject).eq("status", "active"))
      .first();
    if (active) throw new ConvexError("Only one active experiment is allowed");
  }

  const timestamp = now();
  await ctx.db.patch(experiment._id, {
    status: target,
    statusVersion: experiment.statusVersion + 1,
    activeStartedAt: target === "active" ? timestamp : experiment.activeStartedAt,
    completedAt: target === "completed" ? timestamp : undefined,
    cancelledAt: target === "cancelled" ? timestamp : undefined,
    updatedAt: timestamp,
  });
  await ctx.db.insert("experimentEvents", {
    ownerId: identity.subject,
    experimentId: experiment._id,
    action: target === "active" ? "accepted" : target,
    idempotencyKey: args.idempotencyKey,
    note: args.note?.trim() || undefined,
    occurredAt: timestamp,
  });
  return await ctx.db.get(experiment._id);
}

export const accept = mutation({
  args: transitionArgs,
  handler: (ctx, args) => transitionExperiment(ctx, args, "active"),
});

export const complete = mutation({
  args: transitionArgs,
  handler: (ctx, args) => transitionExperiment(ctx, args, "completed"),
});

export const cancel = mutation({
  args: transitionArgs,
  handler: (ctx, args) => transitionExperiment(ctx, args, "cancelled"),
});

export const ingestOvernightSignals = mutation({
  args: {
    localDate: v.string(),
    timezoneOffsetMinutes: v.number(),
    bodyStatus: v.number(),
    restingHeartRate: v.number(),
    nocturnalHrv: v.number(),
    sleepScore: v.number(),
    coverage: v.number(),
    sourceWindowStart: v.number(),
    sourceWindowEnd: v.number(),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity === null) throw new ConvexError("Unauthenticated");
    validateLocalDate(args.localDate);
    if (!Number.isInteger(args.timezoneOffsetMinutes) || Math.abs(args.timezoneOffsetMinutes) > 14 * 60) {
      throw new ConvexError("timezoneOffsetMinutes is invalid");
    }
    if (args.sourceWindowEnd < args.sourceWindowStart) throw new ConvexError("Invalid source window");

    const signals = [
      normalizeProgressSignal({ signalType: "body_status", value: args.bodyStatus, unit: "score", coverage: args.coverage }),
      normalizeProgressSignal({ signalType: "resting_hr", value: args.restingHeartRate, unit: "bpm", coverage: args.coverage }),
      normalizeProgressSignal({ signalType: "hrv", value: args.nocturnalHrv, unit: "ms", coverage: args.coverage }),
      normalizeProgressSignal({ signalType: "sleep_score", value: args.sleepScore, unit: "score", coverage: args.coverage }),
    ];

    const timestamp = now();
    for (const signal of signals) {
      const existing = await ctx.db
        .query("progressSignals")
        .withIndex("by_owner_date_type", (q) => q.eq("ownerId", identity.subject).eq("localDate", args.localDate).eq("signalType", signal.signalType))
        .first();
      const record = {
        ownerId: identity.subject,
        localDate: args.localDate,
        timezoneOffsetMinutes: args.timezoneOffsetMinutes,
        signalType: signal.signalType,
        value: signal.value,
        unit: signal.unit,
        coverage: signal.coverage,
        source: "sensor_bio_sdk" as const,
        algorithmVersion: "body-status-v1",
        sourceWindowStart: args.sourceWindowStart,
        sourceWindowEnd: args.sourceWindowEnd,
        updatedAt: timestamp,
      };
      if (existing) await ctx.db.patch(existing._id, record);
      else await ctx.db.insert("progressSignals", record);
    }
    return { recorded: signals.length };
  },
});

export const listProgress = query({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity === null) throw new ConvexError("Unauthenticated");
    const limit = Math.min(Math.max(Math.floor(args.limit ?? 28), 1), 90);
    const points = await ctx.db
      .query("progressSignals")
      .withIndex("by_owner_date", (q) => q.eq("ownerId", identity.subject))
      .order("desc")
      .take(limit * 4);
    return points.sort((a, b) => a.localDate.localeCompare(b.localDate));
  },
});

export const savePreferences = mutation({
  args: {
    dailyCheckInEnabled: v.boolean(),
    experimentReminderEnabled: v.boolean(),
    quietHoursStartMinutes: v.optional(v.number()),
    quietHoursEndMinutes: v.optional(v.number()),
    timezone: v.string(),
    consentVersion: v.string(),
  },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity === null) throw new ConvexError("Unauthenticated");
    if (!args.timezone.trim() || !args.consentVersion.trim()) throw new ConvexError("timezone and consentVersion are required");
    for (const minute of [args.quietHoursStartMinutes, args.quietHoursEndMinutes]) {
      if (minute !== undefined && (!Number.isInteger(minute) || minute < 0 || minute >= 24 * 60)) {
        throw new ConvexError("quiet hours must be minutes after midnight");
      }
    }
    const timestamp = now();
    const existing = await ctx.db.query("signalPreferences").withIndex("by_owner", (q) => q.eq("ownerId", identity.subject)).first();
    const value = { ...args, ownerId: identity.subject, consentAcceptedAt: timestamp, updatedAt: timestamp };
    if (existing) {
      await ctx.db.patch(existing._id, value);
      return await ctx.db.get(existing._id);
    }
    const id = await ctx.db.insert("signalPreferences", value);
    return await ctx.db.get(id);
  },
});

export const registerPushDevice = mutation({
  args: { token: v.string(), appBuild: v.string() },
  handler: async (ctx, args) => {
    const identity = await ctx.auth.getUserIdentity();
    if (identity === null) throw new ConvexError("Unauthenticated");
    if (!args.token.trim() || !args.appBuild.trim()) throw new ConvexError("token and appBuild are required");
    const existing = await ctx.db
      .query("pushDevices")
      .withIndex("by_owner_token", (q) => q.eq("ownerId", identity.subject).eq("token", args.token))
      .first();
    const timestamp = now();
    if (existing) {
      await ctx.db.patch(existing._id, { appBuild: args.appBuild, updatedAt: timestamp });
      return existing._id;
    }
    return await ctx.db.insert("pushDevices", {
      ownerId: identity.subject,
      token: args.token,
      platform: "ios",
      appBuild: args.appBuild,
      registeredAt: timestamp,
      updatedAt: timestamp,
    });
  },
});
