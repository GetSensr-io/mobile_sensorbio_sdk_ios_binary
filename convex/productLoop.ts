import { ConvexError, v } from "convex/values";
import { internalMutation, internalQuery, type MutationCtx } from "./_generated/server";
import type { Id } from "./_generated/dataModel";
import { allowedTransition } from "./productLoopRules";

const now = () => Date.now();

const demoCatalog = {
  "evening-reset-v1": {
    sourceInsightId: "evening-reset-v1",
    experimentMethodId: "demo-evening-reset",
    title: "Try an evening reset",
    reason: "This three-night demo helps you see how a small, repeatable routine can be tracked over time.",
    instructions: "For three nights, choose a wind-down time, silence nonessential notifications, and keep the last hour before bed low intensity.",
    expectedDurationDays: 3,
  },
} as const;

export const getCurrent = internalQuery({
  args: { demoInstallId: v.string() },
  handler: async (ctx, args) => {
    const [active, proposals, preferences] = await Promise.all([
      ctx.db.query("experiments").withIndex("by_demo_status", (q) => q.eq("demoInstallId", args.demoInstallId).eq("status", "active")).first(),
      ctx.db.query("experiments").withIndex("by_demo_status", (q) => q.eq("demoInstallId", args.demoInstallId).eq("status", "proposed")).collect(),
      ctx.db.query("signalPreferences").withIndex("by_demo", (q) => q.eq("demoInstallId", args.demoInstallId)).first(),
    ]);

    return { active, proposals, preferences };
  },
});

export const createProposal = internalMutation({
  args: {
    demoInstallId: v.string(),
    demoCatalogId: v.literal("evening-reset-v1"),
  },
  handler: async (ctx, args) => {
    const catalogEntry = demoCatalog[args.demoCatalogId];
    const existing = await ctx.db
      .query("experiments")
      .withIndex("by_demo_source", (q) => q.eq("demoInstallId", args.demoInstallId).eq("sourceInsightId", catalogEntry.sourceInsightId))
      .first();
    if (existing) return existing;

    const timestamp = now();
    const id = await ctx.db.insert("experiments", {
      demoInstallId: args.demoInstallId,
      sourceInsightId: catalogEntry.sourceInsightId,
      experimentMethodId: catalogEntry.experimentMethodId,
      title: catalogEntry.title,
      reason: catalogEntry.reason,
      instructions: catalogEntry.instructions,
      expectedDurationDays: catalogEntry.expectedDurationDays,
      status: "proposed",
      statusVersion: 1,
      createdAt: timestamp,
      updatedAt: timestamp,
    });
    return await ctx.db.get(id);
  },
});

const transitionArgs = {
  demoInstallId: v.string(),
  experimentId: v.id("experiments"),
  idempotencyKey: v.string(),
};

async function transitionExperiment(
  ctx: MutationCtx,
  args: { demoInstallId: string; experimentId: Id<"experiments">; idempotencyKey: string },
  target: "active" | "completed" | "cancelled",
) {
  if (!args.idempotencyKey.trim()) throw new ConvexError("idempotencyKey is required");

  const previousEvent = await ctx.db
    .query("experimentEvents")
    .withIndex("by_demo_idempotency", (q) => q.eq("demoInstallId", args.demoInstallId).eq("idempotencyKey", args.idempotencyKey))
    .first();
  if (previousEvent) return await ctx.db.get(previousEvent.experimentId);

  const experiment = await ctx.db.get(args.experimentId);
  if (!experiment || experiment.demoInstallId !== args.demoInstallId) throw new ConvexError("Experiment not found");
  if (!allowedTransition(experiment.status, target)) {
    throw new ConvexError(`Invalid experiment transition: ${experiment.status} -> ${target}`);
  }
  if (target === "active") {
    const active = await ctx.db
      .query("experiments")
      .withIndex("by_demo_status", (q) => q.eq("demoInstallId", args.demoInstallId).eq("status", "active"))
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
    demoInstallId: args.demoInstallId,
    experimentId: experiment._id,
    action: target === "active" ? "accepted" : target,
    idempotencyKey: args.idempotencyKey,
    occurredAt: timestamp,
  });
  return await ctx.db.get(experiment._id);
}

export const accept = internalMutation({
  args: transitionArgs,
  handler: (ctx, args) => transitionExperiment(ctx, args, "active"),
});

export const complete = internalMutation({
  args: transitionArgs,
  handler: (ctx, args) => transitionExperiment(ctx, args, "completed"),
});

export const cancel = internalMutation({
  args: transitionArgs,
  handler: (ctx, args) => transitionExperiment(ctx, args, "cancelled"),
});

export const savePreferences = internalMutation({
  args: {
    demoInstallId: v.string(),
    dailyCheckInEnabled: v.boolean(),
    experimentReminderEnabled: v.boolean(),
  },
  handler: async (ctx, args) => {
    const timestamp = now();
    const existing = await ctx.db.query("signalPreferences").withIndex("by_demo", (q) => q.eq("demoInstallId", args.demoInstallId)).first();
    const value = { ...args, demoInstallId: args.demoInstallId, updatedAt: timestamp };
    if (existing) {
      await ctx.db.patch(existing._id, value);
      return await ctx.db.get(existing._id);
    }
    const id = await ctx.db.insert("signalPreferences", value);
    return await ctx.db.get(id);
  },
});
