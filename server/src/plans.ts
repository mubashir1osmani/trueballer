// The single source of truth for what each plan unlocks. The app reads this
// from GET /v1/me; it never decides its own tier.

export type PlanID = "free" | "plus" | "pro";

export type Feature =
  | "capture" // turn a note into school tasks
  | "braindump" // read a whole morning of sticky notes
  | "weekly_review" // a short written review of the week
  | "coach"; // multi-turn planning conversation

export interface Plan {
  id: PlanID;
  name: string;
  model: string;
  dailyRequests: number;
  features: Feature[];
}

export const PLANS: Record<PlanID, Plan> = {
  free: {
    id: "free",
    name: "Free",
    model: "claude-haiku-4-5",
    dailyRequests: 15,
    features: ["capture", "braindump"],
  },
  plus: {
    id: "plus",
    name: "Plus",
    model: "claude-sonnet-5-5",
    dailyRequests: 60,
    features: ["capture", "braindump", "weekly_review"],
  },
  pro: {
    id: "pro",
    name: "Pro",
    model: "claude-opus-5-5",
    dailyRequests: 150,
    features: ["capture", "braindump", "weekly_review", "coach"],
  },
};

export function planFor(id: string | null | undefined, expiresAt: number | null | undefined, now = Date.now()): Plan {
  const plan = PLANS[(id ?? "free") as PlanID] ?? PLANS.free;
  if (plan.id !== "free" && expiresAt != null && expiresAt * 1000 < now) return PLANS.free;
  return plan;
}

export function publicPlan(plan: Plan) {
  return { id: plan.id, name: plan.name, dailyRequests: plan.dailyRequests, features: plan.features };
}
