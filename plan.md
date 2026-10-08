# Student Time / GPA Planner — Plan (iOS)

**North star:** Help students (15+) manage school + work + internships so they miss fewer deadlines and improve GPA.

**Platform decision (2026-09-26):** Native iOS app — SwiftUI + SwiftData, EventKit for calendar access, **no backend and no accounts for MVP**. All data lives on-device. Rationale:
- EventKit reads every calendar already on the device (school Google account, work account, iCloud) with one permission prompt — replaces the entire Google OAuth + sensitive-scope verification + token storage problem from the web plan.
- No backend → privacy story is nearly free (data never leaves the phone), and there's nothing to deploy or secure.
- Native unlocks the features this app actually wants: local notifications, widgets, and a Focus timer as a lock-screen Live Activity.

**Scope lock**
- In: calendar-first time management for courses, projects, internships, work
- Out for now: LMS / email auto-ingest, homework writing / cheating helpers, Android/web, multi-device sync (CloudKit later if needed)

---

## Progress tracker

| Phase | Status | Notes |
|-------|--------|-------|
| 0 — Foundation (project, shell, settings) | done | 2026-09-26: builds + runs on iPhone 16 sim (iOS 18.5); SwiftData store verified on disk |
| 1a — EventKit calendar access | done | 2026-09-26: verified on sim — explainer, permission, 2 sample accounts' events grouped by day; picker + denied state built |
| 1b — Classify events → Courses screen | done | 2026-09-26: calendar-default + title-pattern rules working; Courses auto-fills on sim. Known gap: one-off events (e.g. "Essay 2 due") show as courses until 1c turns them into tasks |
| 1c — Tasks: quick-add first, calendar-derived second | done | 2026-09-26: quick-add sheet, StudyTask model, deadline suggestions with confirm/dismiss on Today; verified on sim, installed to phone |
| 2 — Home / Today | done | 2026-09-26: Next up (top 3 ranked), free-time summary, today's schedule, swipe done/snooze/reschedule, due-date notifications; verified on sim, installed to phone |
| 3 — Focus timer | done | 2026-09-26: task-linked timer, pause/resume, persistent session history + estimates; Lock Screen / Dynamic Island verified on iPhone 16 sim; 7 tests pass, iPhone Release build passes |
| 4 — GPA / Progress | done | 2026-09-27: manual grades, weighted average, trend, focus effort, entered GPA, at-risk boost on Today |
| 5 — Smarter planning | done | 2026-09-27: week study blocks from tasks + calendar gaps + working hours + sleep; Ask AI drafts school tasks for review |

**Legend:** `not started` → `in progress` → `done`

---

## Phase details

### Phase 0 — Foundation
- [x] Xcode project: SwiftUI app, iOS 17+ target, SwiftData for persistence (XcodeGen `project.yml` — regenerate with `xcodegen generate` after adding files)
- [x] App shell + tab nav: Today | Courses | Calendar | Focus | Progress (Settings via gear icon)
- [x] Settings: work hours, sleep target (notification prefs deferred to Phase 2 when notifications exist)
- [x] SwiftData models: UserSettings (Course, Task, etc. added in their phases)
- **Done when:** app runs in simulator; tabs navigate; settings persist across relaunch
- **No auth.** No accounts, no sign-in. Data is on-device only.

### Phase 1a — EventKit calendar access
- [x] Request calendar permission (`EKEventStore` full access — iOS has no read-only tier; we simply never write) with a pre-permission explainer screen
- [x] List all device calendars grouped by account; user picks which ones count (nil selection = all, so new calendars auto-include)
- [x] Calendar screen: upcoming events (next 2 weeks) from selected calendars, grouped by day
- [x] Handle: permission denied (empty state with Open Settings button), `EKEventStoreChanged` refresh
- **Done when:** events from 2+ accounts (e.g. school + personal) appear in-app on a real device or simulator with test calendars ✓ (sim: sample School + Work calendars)
- **Dev note:** DEBUG-only launch env vars for sim testing: `SEED_SAMPLE_EVENTS=1` creates sample calendars/events (the only code path that ever writes), `INITIAL_TAB=calendar|courses|...` opens a specific tab
- **Note:** if a student's school account isn't on their phone, onboarding points them to Settings → Apps → Calendar → Accounts — still far easier than OAuth.

### Phase 1b — Classification → Courses
- [x] Start dumb: per-calendar default tag (CalendarRule) + title-pattern overrides (TitleRule); title rule wins over calendar default
- [x] Tags: Course | Work | Internship | Project | Personal | Ignore
- [x] Review UI (sheet from Courses tab): "Needs review" section, per-group tag menu (2 taps to fix), calendar-defaults section
- [x] Courses screen auto-populated from Course-tagged groups (events grouped by calendar + normalized title)
- [x] Title changes mid-semester: new title = new untagged group → appears in "Needs review" (re-prompt, no silent splitting)
- **Known gap (accepted):** one-off events on a course-default calendar (e.g. "Essay 2 due") appear as course rows; Phase 1c converts deadline-like events into suggested tasks instead
- **Done when:** Courses screen filled from calendar, not blank forms; a mis-tag is fixable in ≤2 taps
- **Deliberately not:** LLM classification. Revisit only if rule-based demonstrably fails on real calendars.

### Phase 1c — Tasks (quick-add is the primary path)
- [x] Quick-add sheet from Today (+ button): auto-focused title field, due toggle (default: tomorrow 11:59 PM), course picker fed by classification; submit from keyboard
- [x] Timed calendar events stay scheduled blocks (Calendar tab); they are not tasks
- [x] Deadline-looking events (title matches due/exam/quiz/… patterns, incl. all-day and ~11:59 PM starts) → "From your calendar" suggestions on Today with Add / dismiss; dismissals remembered; Ignore-tagged calendars excluded; never auto-created
- **Done when:** Today can rank next actions from tasks; adding an assignment the moment a professor announces it is frictionless
- **Why quick-add first:** most real deadlines live in the LMS (out of scope), not on calendars. Calendar-derived tasks are a bonus, not the backbone.

### Phase 2 — Home / Today
- [x] Next up: top 3 ranked tasks (overdue first, then nearest deadline; dateless last) + free-minutes summary computed from workday window minus today's remaining events
- [x] Today's schedule section: remaining timed events, locked (all-day events don't consume time)
- [x] Done (tap circle or swipe right) / snooze to tomorrow 8 AM / reschedule via date sheet (swipe left)
- [x] Local notifications: opt-in toggle in Settings + lead-time picker (30m/1h/2h/1d); permission requested on enable; reminders re-synced on task changes
- **Done when:** morning open → clear next actions ✓
- **Priority note:** ranking weights deadlines heavily; GPA/at-risk input arrives in Phase 4. Course weight is a Phase 4 input — current score is deadline-driven.

### Phase 3 — Focus
- [x] Timer on current Next task (Today timer button selects a task; Focus defaults to the highest-ranked open task)
- [x] Log actual vs estimated time (optional estimate in Quick Add, editable before Focus; task totals + recent sessions)
- [x] Live Activity: timer on lock screen / Dynamic Island (tap to return to Focus)
- **Done when:** Next → Focus → done with time logged, visible on lock screen ✓ (iPhone 16 simulator, iOS 18.5)
- **Behavior:** Count-up timer; one session at a time. Pause excludes break time. End Session logs time and leaves the task open; Complete Task logs time and completes it. Completing the active task from Today also closes its session.
- **Persistence:** The open session is saved in SwiftData at start/pause/resume; timestamps retain elapsed time across backgrounding and relaunch. Ending updates the same record to avoid duplicate logs. Existing task data migrated successfully.
- **Verification:** Six unit tests cover elapsed time, pause/resume, disk reload, duplicate prevention, completion, and multiple sessions. One UI test covers quick-add → Focus → pause → relaunch → resume → complete → history. Manually verified a ticking Dynamic Island, Lock Screen card, return-to-Focus link, and End Session retaining the task. Release build for iPhone passes with signing disabled; physical-device validation remains a later check.
- **Live Activity limit:** iOS controls visibility and lifetime (up to eight hours active). The saved timer remains usable if Live Activities are disabled or unavailable; returning to the app reconciles its Live Activity.

### Phase 4 — GPA / Progress
- [x] Manual grade entry per course (accepted limitation: manual entry is low-retention; this phase is a lens, not the core)
- [x] Trend + effort (logged focus time) vs outcomes
- [x] Surface at-risk courses into Today priority
- **Done when:** "this course needs more time" from your data ✓

### Phase 5 — Planner polish
- [x] Suggest study blocks around work + sleep (from Settings + calendar gaps)
- [x] Free-hours → GPA-protecting task picks
- **Done when:** week plan mostly builds from tasks + calendars ✓
- **Behavior:** Suggestions appear on Today and Calendar. They are not written to EventKit. Blocks stay inside working hours, end early enough to protect the sleep target, and skip timed events. All-day events do not consume time. Overdue and next-day tasks keep deadline order; later tasks for below-target courses take earlier open time. A block never runs past a future due date.
- **AI boundary:** Ask AI turns a note into school tasks (or, separately, one reminder or calendar event). Apple Intelligence does that on device when the phone has it (iOS 26). Otherwise a date parser fills the same preview. The student confirms before anything is saved. The model does not rank tasks or place study blocks — WeekPlanner does, so a draft cannot land on a shift or during sleep. No cloud model and no API key.

---

## Stack (locked)
- Swift 5.10+, SwiftUI, iOS 17+ minimum target
- SwiftData for persistence (on-device; CloudKit sync is a later opt-in, not MVP)
- EventKit (read-only calendar access)
- UserNotifications (Phase 2), ActivityKit for Live Activities (Phase 3)
- No third-party dependencies until a concrete need appears

## Ship checklist (later, not now)
- Apple Developer Program ($99/yr) needed for device install beyond 7 days, TestFlight, and App Store
- TestFlight beta with real students before any App Store submission
- If accounts are ever added with third-party login, Apple requires Sign in with Apple too

## Safety / privacy
- All data on-device; nothing is uploaded anywhere; no analytics for MVP
- Read-only calendar access; clear pre-permission explainer; works (degraded) if denied
- Calm nudges only (no guilt dark patterns)

## Key decisions (locked)
1. Native iOS (SwiftUI), not web/React Native — EventKit + Live Activities are the product edge
2. No backend, no accounts for MVP — on-device SwiftData only
3. No LMS reading for now — quick-add is the primary task path; calendar classification fills courses
4. Rule-based classification (calendar defaults + title patterns), not LLM
5. Ship one phase at a time
6. Screens: Today, Courses, Calendar, Focus, Progress (+ Settings)
7. AI drafts tasks or a single reminder/event for review, on device. It does not schedule, rank, or classify calendars.

## Dev notes
- Project is generated: edit `project.yml`, then `xcodegen generate` (don't hand-edit the .xcodeproj; it's regenerable)
- Build: `xcodebuild -project StudyPlanner.xcodeproj -scheme StudyPlanner -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build`
- Calendar usage description is already declared in project.yml (needed for Phase 1a)
- Sim testing env vars (DEBUG only, compiled out of Release, pass as `SIMCTL_CHILD_*` to `simctl launch`): `SEED_SAMPLE_EVENTS=1` (create sample School/Work calendars + events), `SEED_SAMPLE_RULES=1` (tag them course/work), `SEED_SAMPLE_TASKS=1` (two sample tasks), `CLEAR_SAMPLE_EVENTS=1` (delete those sample calendars), `INITIAL_TAB=today|courses|calendar|focus|progress`. A normal launch, and every Release build, reads only the calendars and SwiftData store on the device.
- Grant calendar permission in sim: `xcrun simctl privacy <device> grant calendar com.mubashir.StudyPlanner`
- Phase 3 adds the `FocusActivity` WidgetKit extension; shared ActivityKit types live in `Shared/`. Both Info.plists are generated from `project.yml`.
- Test: `xcodebuild -project StudyPlanner.xcodeproj -scheme StudyPlanner -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' -parallel-testing-enabled NO test`
- UI tests add and complete a uniquely named test task in the simulator; they preserve existing tasks and history.

## Changelog
- 2026-09-26: Plan created from design brainstorm; Phase 1 reworked to calendar-first
- 2026-09-26: Replatformed web → native iOS. Google OAuth/backend/auth removed in favor of EventKit + on-device SwiftData. Quick-add promoted to primary task path. Classification mechanism locked (rule-based). Supabase/Clerk decision obsolete.
- 2026-09-26: Phase 0 built and verified in simulator.
- 2026-09-26: Phases 1a + 1b built and verified in simulator (EventKit access, calendar picker, event list, rule-based classification, review UI, auto-filled Courses).
- 2026-09-26: First install on physical iPhone (free personal team, automatic signing).
- 2026-09-26: Phase 1c built and verified (quick-add, StudyTask, deadline suggestions with dismiss memory). Phase 1 complete.
- 2026-09-26: Phase 2 built and verified (Planner ranking + free time, Today rework with schedule + swipe actions, NotificationService + reminder settings).
- 2026-09-26: Phase 3 built and verified (persistent Focus timer, estimates + session history, task completion, ActivityKit / WidgetKit Lock Screen and Dynamic Island timer). Added six persistence/accounting tests and one end-to-end UI test; all pass. Quick Add opens full-height to keep autofocus and the keyboard stable.
- 2026-09-27: Phase 4 marked done (grade entry, trend, effort, GPA, at-risk priority were already in the app). Phase 5 adds the week study plan and extends Ask AI so a note can become reviewed school tasks, with a date parser when Apple Intelligence is unavailable.
- 2026-09-27: Selling point is intentional time. "Plan my way" stores the student's own rules on device (when they study, block length, daily cap, reminders) and the week plan follows them after they confirm.
