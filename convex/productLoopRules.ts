export const experimentStatuses = ["proposed", "active", "completed", "cancelled"] as const;
export type ExperimentStatus = (typeof experimentStatuses)[number];

export const progressSignalTypes = [
  "body_status",
  "sleep_score",
  "sleep_duration",
  "resting_hr",
  "hrv",
  "adherence",
] as const;
export type ProgressSignalType = (typeof progressSignalTypes)[number];

export function allowedTransition(from: ExperimentStatus, to: ExperimentStatus): boolean {
  return (
    (from === "proposed" && (to === "active" || to === "cancelled")) ||
    (from === "active" && (to === "completed" || to === "cancelled"))
  );
}

export function normalizeProgressSignal(input: {
  signalType: string;
  value: number;
  unit: string;
  coverage: number;
}): { signalType: ProgressSignalType; value: number; unit: string; coverage: number } {
  if (!progressSignalTypes.includes(input.signalType as ProgressSignalType)) {
    throw new Error("Unsupported progress signal");
  }
  if (!Number.isFinite(input.value)) {
    throw new Error("Progress value must be finite");
  }
  if (!Number.isFinite(input.coverage) || input.coverage < 0 || input.coverage > 1) {
    throw new Error("Progress coverage must be between 0 and 1");
  }
  if (!input.unit.trim()) {
    throw new Error("Progress unit is required");
  }

  return {
    signalType: input.signalType as ProgressSignalType,
    value: input.value,
    unit: input.unit,
    coverage: input.coverage,
  };
}
