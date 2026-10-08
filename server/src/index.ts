import Anthropic from "@anthropic-ai/sdk";
import { Hono } from "hono";
import { z } from "zod";
import { captureTasks, readBraindump, type NoteContext } from "./ai";
import { AuthError, issueSession, verifyIdentityToken, verifySession } from "./auth";
import { planFor, publicPlan, type Feature } from "./plans";

export interface Env {
  DB: D1Database;
  ANTHROPIC_API_KEY: string;
  SESSION_SECRET: string;
  APPLE_BUNDLE_ID: string;
  GOOGLE_IOS_CLIENT_ID: string;
}

type Vars = { userID: string };
const app = new Hono<{ Bindings: Env; Variables: Vars }>();

const nowSeconds = () => Math.floor(Date.now() / 1000);
const today = () => new Date().toISOString().slice(0, 10);

app.onError((err, c) => {
  // Never log request bodies: they can contain a student's notes.
  console.error("request failed", c.req.method, c.req.path, err.name);
  if (err instanceof AuthError) return c.json({ error: "unauthorized" }, 401);
  if (err instanceof Anthropic.RateLimitError) return c.json({ error: "busy" }, 503);
  if (err instanceof Anthropic.APIError) return c.json({ error: "ai_unavailable" }, 502);
  return c.json({ error: "server_error" }, 500);
});

app.get("/health", (c) => c.json({ ok: true }));

// MARK: Sign in

const SignIn = z.object({
  provider: z.enum(["apple", "google"]),
  idToken: z.string().min(20).max(8192),
  nonce: z.string().min(16).max(256),
});

app.post("/v1/auth/signin", async (c) => {
  const body = SignIn.safeParse(await c.req.json().catch(() => null));
  if (!body.success) return c.json({ error: "bad_request" }, 400);
  let identity;
  try {
    identity = await verifyIdentityToken(body.data.provider, body.data.idToken, body.data.nonce, {
      appleBundleID: c.env.APPLE_BUNDLE_ID,
      googleClientID: c.env.GOOGLE_IOS_CLIENT_ID,
    });
  } catch {
    return c.json({ error: "unauthorized" }, 401);
  }

  const db = c.env.DB;
  const existing = await db
    .prepare("SELECT user_id FROM identities WHERE provider = ? AND subject = ?")
    .bind(identity.provider, identity.subject)
    .first<{ user_id: string }>();

  let userID = existing?.user_id;
  if (!userID) {
    userID = crypto.randomUUID();
    const now = nowSeconds();
    await db.batch([
      db.prepare("INSERT INTO users (id, created_at) VALUES (?, ?)").bind(userID, now),
      db
        .prepare("INSERT INTO identities (provider, subject, user_id, created_at) VALUES (?, ?, ?, ?)")
        .bind(identity.provider, identity.subject, userID, now),
    ]);
  }
  const session = await issueSession(userID, c.env.SESSION_SECRET);
  return c.json({ ...session, isNewUser: !existing });
});

// MARK: Authenticated routes

app.use("/v1/me/*", requireSession);
app.use("/v1/me", requireSession);
app.use("/v1/ai/*", requireSession);

async function requireSession(c: any, next: () => Promise<void>) {
  const header = c.req.header("Authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token) return c.json({ error: "unauthorized" }, 401);
  try {
    c.set("userID", await verifySession(token, c.env.SESSION_SECRET));
  } catch {
    return c.json({ error: "unauthorized" }, 401);
  }
  await next();
}

interface UserRow {
  plan: string;
  plan_expires_at: number | null;
  ai_consent_at: number | null;
}

async function loadUser(db: D1Database, userID: string) {
  return db.prepare("SELECT plan, plan_expires_at, ai_consent_at FROM users WHERE id = ?").bind(userID).first<UserRow>();
}

async function usedToday(db: D1Database, userID: string) {
  const row = await db
    .prepare("SELECT requests FROM usage WHERE user_id = ? AND day = ?")
    .bind(userID, today())
    .first<{ requests: number }>();
  return row?.requests ?? 0;
}

app.get("/v1/me", async (c) => {
  const user = await loadUser(c.env.DB, c.var.userID);
  if (!user) return c.json({ error: "unauthorized" }, 401);
  const plan = planFor(user.plan, user.plan_expires_at);
  return c.json({
    plan: publicPlan(plan),
    usedToday: await usedToday(c.env.DB, c.var.userID),
    aiConsent: user.ai_consent_at != null,
  });
});

app.post("/v1/me/consent", async (c) => {
  const body = z.object({ granted: z.boolean() }).safeParse(await c.req.json().catch(() => null));
  if (!body.success) return c.json({ error: "bad_request" }, 400);
  await c.env.DB.prepare("UPDATE users SET ai_consent_at = ? WHERE id = ?")
    .bind(body.data.granted ? nowSeconds() : null, c.var.userID)
    .run();
  return c.json({ aiConsent: body.data.granted });
});

// App Store guideline 5.1.1(v): accounts must be deletable from inside the app.
app.delete("/v1/me", async (c) => {
  await c.env.DB.prepare("DELETE FROM users WHERE id = ?").bind(c.var.userID).run();
  return c.body(null, 204);
});

// MARK: AI

const NoteRequest = z.object({
  note: z.string().trim().min(1).max(4000),
  courses: z.array(z.string().max(120)).max(40),
  now: z.string().max(40),
  timeZone: z.string().max(64),
});

function aiRoute(feature: Feature, handler: typeof captureTasks | typeof readBraindump) {
  return async (c: any) => {
    const body = NoteRequest.safeParse(await c.req.json().catch(() => null));
    if (!body.success) return c.json({ error: "bad_request" }, 400);

    const db: D1Database = c.env.DB;
    const userID: string = c.var.userID;
    const user = await loadUser(db, userID);
    if (!user) return c.json({ error: "unauthorized" }, 401);
    if (user.ai_consent_at == null) return c.json({ error: "consent_required" }, 403);

    const plan = planFor(user.plan, user.plan_expires_at);
    if (!plan.features.includes(feature)) return c.json({ error: "upgrade_required", feature }, 402);

    // Reserve the request before calling Claude so concurrent calls can't overrun the quota.
    const reserved = await db
      .prepare(
        `INSERT INTO usage (user_id, day, requests) VALUES (?1, ?2, 1)
         ON CONFLICT (user_id, day) DO UPDATE SET requests = requests + 1
         WHERE requests < ?3
         RETURNING requests`,
      )
      .bind(userID, today(), plan.dailyRequests)
      .first<{ requests: number }>();
    if (!reserved) return c.json({ error: "quota_exceeded", limit: plan.dailyRequests }, 429);

    const refund = () =>
      db.prepare("UPDATE usage SET requests = MAX(requests - 1, 0) WHERE user_id = ? AND day = ?").bind(userID, today()).run();
    const client = new Anthropic({ apiKey: c.env.ANTHROPIC_API_KEY, maxRetries: 1 });
    let outcome;
    try {
      outcome = await handler(client, plan, body.data as NoteContext);
    } catch (err) {
      await refund();
      throw err;
    }
    if (!outcome.ok) {
      await refund();
      return c.json({ error: outcome.reason }, 422);
    }

    await db
      .prepare("UPDATE usage SET input_tokens = input_tokens + ?, output_tokens = output_tokens + ? WHERE user_id = ? AND day = ?")
      .bind(outcome.usage.input, outcome.usage.output, userID, today())
      .run();
    return c.json({ result: outcome.value, model: plan.id, remaining: plan.dailyRequests - reserved.requests });
  };
}

app.post("/v1/ai/capture", aiRoute("capture", captureTasks));
app.post("/v1/ai/braindump", aiRoute("braindump", readBraindump));

export default app;
