import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

const experimentStatus = v.union(
  v.literal("proposed"),
  v.literal("active"),
  v.literal("completed"),
  v.literal("cancelled"),
);

export default defineSchema({
  experiments: defineTable({
    ownerId: v.string(),
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
    .index("by_owner_source", ["ownerId", "sourceInsightId"])
    .index("by_owner_status", ["ownerId", "status"]),

  experimentEvents: defineTable({
    ownerId: v.string(),
    experimentId: v.id("experiments"),
    action: v.union(v.literal("accepted"), v.literal("completed"), v.literal("cancelled"), v.literal("adherence")),
    idempotencyKey: v.string(),
    occurredAt: v.number(),
    note: v.optional(v.string()),
  }).index("by_owner_idempotency", ["ownerId", "idempotencyKey"]),

  progressSignals: defineTable({
    ownerId: v.string(),
    experimentId: v.optional(v.id("experiments")),
    localDate: v.string(),
    timezoneOffsetMinutes: v.number(),
    signalType: v.union(
      v.literal("body_status"),
      v.literal("sleep_score"),
      v.literal("sleep_duration"),
      v.literal("resting_hr"),
      v.literal("hrv"),
      v.literal("adherence"),
    ),
    value: v.number(),
    unit: v.string(),
    coverage: v.number(),
    source: v.union(v.literal("sensor_bio_sdk"), v.literal("experiment_adherence")),
    algorithmVersion: v.string(),
    sourceWindowStart: v.number(),
    sourceWindowEnd: v.number(),
    updatedAt: v.number(),
  })
    .index("by_owner_date_type", ["ownerId", "localDate", "signalType"])
    .index("by_owner_date", ["ownerId", "localDate"]),

  signalPreferences: defineTable({
    ownerId: v.string(),
    dailyCheckInEnabled: v.boolean(),
    experimentReminderEnabled: v.boolean(),
    quietHoursStartMinutes: v.optional(v.number()),
    quietHoursEndMinutes: v.optional(v.number()),
    timezone: v.string(),
    consentVersion: v.string(),
    consentAcceptedAt: v.number(),
    updatedAt: v.number(),
  }).index("by_owner", ["ownerId"]),

  pushDevices: defineTable({
    ownerId: v.string(),
    token: v.string(),
    platform: v.literal("ios"),
    appBuild: v.string(),
    registeredAt: v.number(),
    updatedAt: v.number(),
  }).index("by_owner_token", ["ownerId", "token"]),
});
