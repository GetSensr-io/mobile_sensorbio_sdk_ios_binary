import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

const experimentStatus = v.union(
  v.literal("proposed"),
  v.literal("active"),
  v.literal("completed"),
  v.literal("cancelled"),
);

// Convex holds fictional Suggested Experiment state for the demo only.
// Sensor-derived measurements, raw PPG, account IDs, and device tokens stay out of this schema.
export default defineSchema({
  experiments: defineTable({
    demoInstallId: v.string(),
    sourceInsightId: v.string(),
    experimentMethodId: v.optional(v.string()),
    title: v.string(),
    reason: v.string(),
    instructions: v.string(),
    expectedDurationDays: v.number(),
    status: experimentStatus,
    statusVersion: v.number(),
    activeStartedAt: v.optional(v.number()),
    completedAt: v.optional(v.number()),
    cancelledAt: v.optional(v.number()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_demo_source", ["demoInstallId", "sourceInsightId"])
    .index("by_demo_status", ["demoInstallId", "status"]),

  experimentEvents: defineTable({
    demoInstallId: v.string(),
    experimentId: v.id("experiments"),
    action: v.union(v.literal("accepted"), v.literal("completed"), v.literal("cancelled"), v.literal("adherence")),
    idempotencyKey: v.string(),
    occurredAt: v.number(),
  }).index("by_demo_idempotency", ["demoInstallId", "idempotencyKey"]),

  signalPreferences: defineTable({
    demoInstallId: v.string(),
    dailyCheckInEnabled: v.boolean(),
    experimentReminderEnabled: v.boolean(),
    updatedAt: v.number(),
  }).index("by_demo", ["demoInstallId"]),
});
