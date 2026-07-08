# DoneFirst — Product Requirements Document & Ideal Customer Profile

---

## PART I: Ideal Customer Profile (ICP)

### Primary Persona: Busy Working Parent

| Attribute | Detail |
|-----------|--------|
| **Age** | 30–45 |
| **Occupation** | Full-time professional (tech, healthcare, finance, education, remote worker) |
| **Household** | Dual-income family with 1–3 school-age children (ages 6–17) |
| **Pain Point** | Cannot physically supervise homework time due to work schedule; child gets distracted by phones/tablets/gaming consoles |
| **Current Solution** | Yelling, taking devices away manually, checking homework after the fact — inconsistent and exhausting |
| **Tech Comfort** | Uses a smartphone daily; comfortable installing apps, managing settings/permissions |
| **Device** | Parent: iPhone or Android. Child: Has own phone or tablet (often hand-me-down) |
| **Geography** | North America / English-speaking markets initially |
| **Income** | $60k–$150k household; willing to pay $5–10/mo for measurable relief |
| **Motivation** | "I want my kids to do their homework without me having to stand over them. I want proof it's done, not just their word." |

### Secondary Persona: The Child (Ages 8–16)

| Attribute | Detail |
|-----------|--------|
| **Age range** | 8–16 |
| **Device behavior** | Has a phone/tablet; uses TikTok, Instagram, Snapchat, YouTube, Roblox, Minecraft |
| **Homework style** | Avoids it until last minute; easily distracted by notifications |
| **Motivation** | Wants access to apps/games; willing to do homework in exchange for screen time |
| **Tech ability** | Proficient with phones; can take photos, submit forms, navigate simple UIs |

### Tertiary Persona: Co-Parent / Caregiver

| Attribute | Detail |
|-----------|--------|
| **Role** | Spouse, ex-spouse, grandparent, or nanny who shares supervision duties |
| **Need** | Visibility into the same session data and ability to approve proofs without sharing a device |

### Anti-Persona (Who This Is NOT For)

- **Homeschooling families** who are present during schoolwork (different problem space)
- **Parents of children under 6** (not developmentally appropriate)
- **Children without their own device** (app requires the child to interact with it)
- **Parents seeking academic tutoring** (this is an accountability tool, not a teaching tool)

---

## PART II: Product Requirements Document (PRD)

### 1. Product Overview

**DoneFirst** is a mobile accountability platform that enforces a "homework first, apps after" rule. Parents set a lock duration, select which apps to block, and the child's device locks those apps until the child submits photo proof that homework is complete. Mistral AI verifies the photo shows actual schoolwork. Parents can approve or override. Streaks and stats gamify the habit.

**Tagline:** *Homework first. Apps after.*

**Platform:** Cross-platform mobile (Flutter) — Android (MVP launch target), iOS (pending Apple Developer Program + FamilyControls entitlement)

**Business Model:** Freemium — Free tier (3 sessions/month, 1 child, basic AI) → Plus tier ($4.99/mo, 30 sessions, 5 children, schedules & streaks) → Pro tier ($9.99/mo, unlimited, advanced AI, co-parenting)

---

### 2. User Stories

#### Authentication & Onboarding

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-01 | Sign up | As a parent, I can create an account with email + password so I can set up my family. | P0 |
| US-02 | Verify email | As a parent, I can verify my email (or skip) after sign-up to secure my account. | P0 |
| US-03 | Onboarding | As a new user, I see a 3-page intro explaining app blocking, photo proof, and streaks. | P1 |
| US-04 | Sign in | As a returning parent, I can sign in with email + password to see my dashboard. | P0 |
| US-05 | Reset password | As a parent, I can reset my password via email if I forget it. | P1 |
| US-06 | Change password | As a parent, I can change my password from settings. | P1 |

#### Parent Dashboard

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-07 | View children | As a parent, I see all my children on the dashboard with their lock status (idle/locked). | P0 |
| US-08 | Add child | As a parent, I can add a child profile with name, color, and emoji avatar. | P0 |
| US-09 | Quick lock | As a parent, I can start a homework lock for any child with one tap using presets. | P0 |
| US-10 | Kid View | As a parent, I can tap "Kid View" to see what the child sees during a session. | P0 |
| US-11 | Family stats | As a parent, I can see aggregate stats (sessions, minutes, approvals) across all children. | P1 |
| US-12 | Today's schedule | As a parent, I see today's recurring schedules on the dashboard with "Start Now" buttons. | P1 |
| US-13 | Notification badge | As a parent, I see an unread notification count badge on the dashboard bell icon. | P1 |
| US-14 | Edit child | As a parent, I can long-press a child card to rename or delete the child. | P1 |

#### Lock Configuration & Presets

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-15 | Set duration | As a parent, I can choose lock duration (30m/45m/1h/1.5h/2h). | P0 |
| US-16 | Set max lift | As a parent, I can set an auto-lift time after which the lock automatically releases. | P1 |
| US-17 | Choose approval mode | As a parent, I can pick Strict (AI decides), Balanced (AI recommends + parent decides), or Parent Only. | P0 |
| US-18 | Select app packs | As a parent, I can pick app categories to block (Social, Games, Entertainment, All). | P0 |
| US-19 | Save presets | As a parent, I can save a lock configuration as a named preset and reuse it later. | P1 |
| US-20 | Load presets | As a parent, I can load and start a session from a saved preset. | P1 |
| US-21 | Delete presets | As a parent, I can delete saved presets I no longer need. | P1 |

#### Active Lock Session

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-22 | See timer | As a child, I see a live countdown timer showing elapsed and remaining time. | P0 |
| US-23 | Add tasks | As a child, I can add homework tasks (with subject tags) during the session. | P0 |
| US-24 | Submit proof | As a child, I can take/upload photos of completed work as proof for each task. | P0 |
| US-25 | Multiple photos | As a child, I can submit multiple photos per proof, viewable in a swipeable gallery. | P1 |
| US-26 | Kid note | As a child, I can add an optional text note when submitting proof (e.g., "Check page 2"). | P1 |
| US-27 | Request break | As a child, I can request a 5-minute break; parent approves/denies. | P0 |
| US-28 | See streak | As a child, I see my current streak (days of consecutive completed sessions). | P1 |
| US-29 | View history | As a child, I can tap "My History" to see my past sessions and proofs. | P1 |
| US-30 | Pause/resume | As a parent, I can pause and resume the active lock timer. | P1 |
| US-31 | Extend lock | As a parent, I can extend the lock by +15 or +30 minutes. | P1 |
| US-32 | Unlock early | As a parent, I can unlock the device early (before timer expires). | P0 |

#### Proof Review & Approval

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-33 | Review proofs | As a parent, I see all submitted proofs with AI verdict and confidence score. | P0 |
| US-34 | Approve proof | As a parent, I can approve a proof, marking the task complete. | P0 |
| US-35 | Reject proof | As a parent, I can reject a proof with a note explaining why. | P0 |
| US-36 | Parent note | As a parent, I can add a note when approving/rejecting (e.g., "Show all problems"). | P1 |
| US-37 | Batch approve | As a parent, I can approve all pending proofs at once with one tap. | P1 |
| US-38 | Search & filter | As a parent, I can search proofs by status and filter by date range in Session History. | P1 |
| US-39 | AI verification | As a parent, I see Mistral AI's analysis of each photo (confidence, match status). | P0 |
| US-40 | Auto-approve math | As a parent, I can enable auto-approve for math proofs (subject-based). | P2 |

#### Proof Gallery & Viewer

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-41 | Gallery grid | As a parent, I can view all proof photos in a 3-column grid with color-coded borders (green=approved, red=rejected). | P1 |
| US-42 | Photo badge | As a parent, I see a "1/3" badge on thumbnails when multiple photos exist. | P1 |
| US-43 | Full-screen viewer | As a parent/child, I can tap a photo to view it full-screen with pinch-to-zoom. | P0 |
| US-44 | Swipe images | As a user, I can swipe between multiple photos in the viewer with dot indicators. | P1 |
| US-45 | AI overlay | As a user, I see the AI result panel (verdict, confidence, reason) below the photo. | P0 |

#### Recurring Schedules

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-46 | Add schedule | As a parent, I can set recurring homework sessions by day of week (Mon–Sun). | P1 |
| US-47 | Remove schedule | As a parent, I can delete a recurring schedule. | P1 |
| US-48 | Quick start | As a parent, I can start a lock from a schedule with one tap. | P1 |

#### Stats & Streaks

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-49 | Child stats | As a parent, I see per-child stats: total sessions, total time, completion rate, proofs approved. | P1 |
| US-50 | Weekly chart | As a parent, I see a 7-day bar chart of study minutes. | P1 |
| US-51 | Streak computation | The system tracks consecutive-day session completions for each child. | P1 |
| US-52 | Streak display | The child sees their streak prominently on the Kid Home screen (⭐ emoji, fire emoji at 7+). | P1 |

#### Notifications

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-53 | Proof submitted | As a parent, I get a notification when a child submits proof. | P1 |
| US-54 | Break requested | As a parent, I get a notification when a child requests a break. | P1 |
| US-55 | Session complete | As a parent, I get a notification when a session is completed. | P1 |
| US-56 | Notification center | As a parent, I can view all notifications in a dedicated screen. | P1 |
| US-57 | Mark read | As a parent, I can mark notifications as read (individually or all at once). | P1 |
| US-58 | Swipe dismiss | As a parent, I can swipe to dismiss notifications. | P2 |

#### Child Profile Management

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-59 | Customize avatar | As a child/parent, I can set the child's emoji and color for personalized display. | P0 |
| US-60 | Edit name | As a parent, I can change the child's display name. | P0 |
| US-61 | View streak | As a parent, I can see the child's current streak count on their profile. | P1 |

#### Settings & Account

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-62 | Edit profile | As a parent, I can edit my name and family name. | P1 |
| US-63 | Dark mode | As a user, I can toggle between light and dark theme. | P1 |
| US-64 | Set PIN | As a parent, I can set a 4-digit PIN for gating sensitive actions. | P1 |
| US-65 | Change password | As a parent, I can change my account password. | P1 |
| US-66 | Notification prefs | As a parent, I can toggle which notification types I receive. | P1 |
| US-67 | Default duration | As a parent, I can set the default lock duration for quick locks. | P2 |
| US-68 | Delete account | As a parent, I can permanently delete my account and all associated data. | P1 |
| US-69 | View plan | As a parent, I can see my current subscription plan and usage. | P1 |
| US-70 | Upgrade | As a parent, I can upgrade from Free to Plus or Pro. | P1 |

#### Co-Parenting

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-71 | Invite co-parent | As a parent, I can invite another parent by email to share supervision. | P1 |
| US-72 | Accept invite | As a parent, I can accept an invitation to co-parent. | P1 |
| US-73 | Cancel invite | As a parent, I can cancel a pending invitation. | P1 |
| US-74 | View co-parents | As a parent, I can see the list of co-parents in my family. | P1 |

#### Device Blocking

| ID | Title | Description | Priority |
|----|-------|-------------|----------|
| US-75 | Block apps | When a lock session starts, the child's selected apps are blocked at the OS level. | P0 |
| US-76 | Show overlay | During a lock, a persistent overlay reminds the child apps are locked. | P1 |
| US-77 | Unblock on complete | When all tasks are approved OR the timer expires, apps are unblocked. | P0 |
| US-78 | Permission handling | The app requests and handles device permissions (Usage Stats, Accessibility) gracefully. | P0 |

---

### 3. Non-Functional Requirements

| ID | Requirement | Detail |
|----|-------------|--------|
| NFR-01 | **Cross-platform** | Must run on Android (minimum) and iOS (with entitlements). Chrome target for dev testing. |
| NFR-02 | **Offline resilience** | App should handle brief network interruptions without losing session state. |
| NFR-03 | **Auth security** | API keys (Supabase anon key, Mistral API key) must never be exposed in client-side code in production; use Supabase RLS + edge functions. |
| NFR-04 | **AI latency** | Mistral AI verification should complete within 5 seconds of photo upload. |
| NFR-05 | **Photo storage** | Proof photos stored in Supabase Storage; auto-cleanup or archival after 90 days. |
| NFR-06 | **Timer accuracy** | Session timer must be consistent (±2 seconds) even if app is backgrounded. |
| NFR-07 | **No state management lib** | MVP uses `setState` + direct Supabase queries; consider Riverpod/Bloc for post-MVP. |
| NFR-08 | **Model consistency** | All data currently passed as `Map<String, dynamic>`; post-MVP should introduce typed models for all entities. |
| NFR-09 | **Test coverage** | Minimum: unit tests for services, widget tests for critical screens (dashboard, lock active). |

---

### 4. Database Schema (Supabase PostgreSQL)

#### Tables

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| `families` | Groups parents for co-parenting | `id`, `name` |
| `parents` | Parent accounts | `id`, `email`, `display_name`, `family_id` |
| `children` | Child profiles | `id`, `parent_id`, `name`, `color`, `emoji`, `streak_count`, `last_streak_date` |
| `homework_sessions` | Lock session instances | `id`, `child_id`, `parent_id`, `status`, `started_at`, `min_lock_minutes`, `max_lift_minutes`, `approval_mode` |
| `homework_tasks` | Tasks within a session | `id`, `session_id`, `description`, `subject` |
| `proof_submissions` | Photo proof records | `id`, `session_id`, `task_id`, `image_url`, `image_urls[]`, `status`, `parent_note`, `ai_result` |
| `break_requests` | Break requests during sessions | `id`, `session_id`, `child_id`, `status` |
| `recurring_schedules` | Weekly schedule templates | `id`, `child_id`, `day_of_week`, `duration_minutes`, `approval_mode` |
| `lock_presets` | Saved lock configurations | `id`, `parent_id`, `name`, `min_lock_minutes`, `max_lift_minutes`, `approval_mode`, `selected_packs[]` |
| `notifications` | In-app notifications | `id`, `parent_id`, `child_id`, `type`, `title`, `body`, `read` |
| `parent_invites` | Co-parent invitations | `id`, `family_id`, `inviter_id`, `invitee_email`, `status` |

**Storage bucket:** `proof-photos` — for uploaded proof images.

---

### 5. Technology Stack

| Layer | Choice | Rationale |
|-------|--------|-----------|
| **Frontend** | Flutter 3.44+ / Dart 3.12+ | Cross-platform from single codebase |
| **Backend** | Supabase | Auth, PostgreSQL database, file storage, real-time subscriptions |
| **AI Verification** | Mistral AI (`mistral-small-latest`) | Vision API for photo analysis; $0.15/M input tokens |
| **Device Blocking** | `flutter_screentime` | Cross-platform app blocking bridge |
| **State Management** | `setState` + `ValueNotifier` | Minimal for MVP; no additional dependency |
| **Theme** | Material 3 | Modern look, built-in dark mode support |

---

### 6. Success Metrics

| Metric | Target (3 months post-launch) |
|--------|-------------------------------|
| **Sessions started** | >500/week |
| **Sessions completed** | >60% completion rate |
| **Proofs submitted** | >2 proofs per session average |
| **AI verification accuracy** | >85% approval of genuine homework |
| **Parent retention** | >40% Week-4 retention |
| **Upgrade conversion** | >5% of free users to Plus/Pro |
| **Children per family** | Average 1.8 |
| **App Store rating** | >4.0 stars |

---

### 7. Competitive Landscape

| Competitor | Strength | Weakness | DoneFirst Advantage |
|------------|----------|----------|---------------------|
| **Screen Time (Apple)** | Built-in, free | No homework verification, no proof requirement | Photo proof with AI verification |
| **Family Link (Google)** | Built-in, free | Same as Apple — no accountability loop | Task + proof workflow, parent override |
| **OurPact** | Blocking + scheduling | $9.99/mo, complex setup, no AI verification | Simpler, cheaper, AI-powered proof |
| **Bark** | Monitoring focus | No homework workflow | Purpose-built for homework accountability |
| **Manual parenting** | Free | Inconsistent, stressful | Structured, automated, trackable |

---

### 8. Monetization

| Tier | Price | Limits |
|------|-------|--------|
| **Free** | $0 | 3 sessions/month, 1 child, basic AI verification |
| **Plus** | $4.99/mo | 30 sessions/month, 5 children, schedules & streaks, priority AI |
| **Pro** | $9.99/mo | Unlimited sessions, unlimited children, advanced AI, co-parenting, priority support |

---

### 9. Development Roadmap

| Phase | Scope | Status |
|-------|-------|--------|
| **MVP (v1.0)** | Auth, Dashboard, Lock Config, Lock Active, Task Entry, Proof Capture, Proof Review, Kid Home, Device Blocking (basic), Onboarding | ✅ Complete |
| **v1.1** | Email verification, Search/filter, Streaks, Multiple photos, Kid History, Lock Presets, Notification Center | ✅ Complete |
| **v1.2** | Batch approve, Parent notes, Kid notes on proof, Subject tags, Recurring schedules, Family stats, Change password | ✅ Complete |
| **v2.0** | Co-parenting, PIN gate, Upgrade screen, Dark mode polish, Focus overlay | ✅ Complete |
| **Post-MVP** | Run SQL migrations in production, End-to-end testing, iOS FamilyControls entitlement, Push notifications, Typed models, Riverpod/Bloc migration, Edge functions for AI verification, Multi-language support, Analytics dashboard |

---

### 10. Known Gaps & Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| **iOS FamilyControls entitlement** | Blocks iOS ship | 2+ week lead time to apply; MVP targets Android + Chrome |
| **Emulator boot failure** | Slows testing | Chrome target (`flutter run -d chrome`) works for most flows |
| **SQL migrations not applied** | Missing features | Run `schema_migrations.sql` in Supabase SQL Editor |
| **No offline support** | App breaks without internet | Acceptable for MVP; most usage is at home with WiFi |
| **Single-device share** | Parent & kid share one device | "Kid View" button on dashboard; post-MVP: separate devices |
| **App blocking reliability** | Weak on Android without Accessibility Service | Document requirement; `flutter_screentime` no-op fallback |
| **Mistral API costs** | Scales with usage | Free tier limits absorb cost; Plus/Pro covers heavier users |
| **No typed data models** | Fragile code | Post-MVP: generate models from Supabase schema |
