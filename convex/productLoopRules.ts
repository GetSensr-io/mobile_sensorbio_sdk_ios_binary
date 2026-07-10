export const experimentStatuses = ["proposed", "active", "completed", "cancelled"] as const;
export type ExperimentStatus = (typeof experimentStatuses)[number];

export function allowedTransition(from: ExperimentStatus, to: ExperimentStatus): boolean {
  return (
    (from === "proposed" && (to === "active" || to === "cancelled")) ||
    (from === "active" && (to === "completed" || to === "cancelled"))
  );
}
