# DoneFirst — Complete Figma Design Spec

## Design System

| Token | Value | Usage |
|-------|-------|-------|
| Primary | `#6C3FC5` | Buttons, active states, icons |
| Primary Light | `#9B7FD4` | Dark mode accent |
| Accent | `#FF8C42` | Timer, badges, highlights |
| Success | `#2ECC71` | Approved, complete |
| Danger | `#E74C3C` | Rejected, delete, errors |
| Warning | `#F39C12` | Pending, attention |
| Info | `#3498DB` | Info cards, AI decisions |
| Surface | `#F8F6FC` | Light mode background |
| Card Light | `#FFFFFF` | Cards (light) |
| Card Dark | `#1E1E2E` | Cards (dark) |
| Text Primary | `#1A1A2E` | Headings, body |
| Text Secondary | `#6B7280` | Subtitles, hints |
| Border | `#E5E7EB` | Card borders |
| Dark BG | `#121212` | Scaffold (dark) |

**Typography:** Material 3 defaults
**Shape:** BorderRadius 10-12 (cards, buttons), 8 (small containers), Circular (avatars)
**Spacing:** 8px grid multiplier
**Buttons:** FilledButton (primary bg), OutlinedButton (primary border), TextButton (no bg)

---

## Screen 1: Splash / Entry
**File:** `main.dart`

- Centered purple circle icon `Icons.check_circle_outline`
- "DoneFirst" in bold 28pt
- "Homework first. Apps after." in secondary 16pt
- CircularProgressIndicator below
- On auth check → navigates to Auth or Dashboard

---

## Screen 2: Auth Screen
**File:** `auth_screen.dart`

**Layout:**
- Centered purple circle icon (check_circle_outline, 40px)
- "DoneFirst" 28pt bold
- "Homework first. Apps after." 15pt secondary
- **Sign-up mode:** Name field appears first
- Email field (prefix: email icon)
- Password field (prefix: lock icon, suffix: "6+ chars" in sign-up)
- "Sign Up" / "Sign In" primary button (full width)
- "Forgot password?" text button (sign-in only)
- Toggle link: "Already have an account? Sign in" / "New? Create an account"

---

## Screen 3: Verify Email Screen
**File:** `verify_email_screen.dart`

**Layout:**
- Centered accent circle icon `Icons.mark_email_unread` (48px)
- "Verify your email" 24pt bold
- "We sent a verification link to\nyour@email.com" 15pt
- "Click the link in the email, then come back." 13pt
- **Primary button:** "I've Verified — Continue" (icon: refresh)
- **Secondary button:** "Resend Email" (icon: send)
- **Skip link:** "Skip — I'll verify later" in secondary color

---

## Screen 4: Onboarding (4-page wizard)
**File:** `onboarding_screen.dart`

**Page 1 — Welcome:** Phone illustration + "Homework First" + "Set homework time, block distractions"
**Page 2 — Block:** Shield icon + "App Blocking" + "Social media, games & entertainment locked"
**Page 3 — Verify:** Camera icon + "Proof Photos" + "Snap a photo of completed work"
**Page 4 — Reward:** Check icon + "Earn Freedom" + "Parents approve, apps unlock"

**Controls:** Dot indicators (4), "Skip" top-right, "Next" / "Get Started" bottom-right

---

## Screen 5: Parent Dashboard
**File:** `parent_dashboard.dart`

**AppBar:** "DoneFirst" with check_circle_outline icon
**Actions:** Refresh, Notifications (badge with unread count), Settings (gear), Sign Out

**Top section:**
- Session usage card: "X / 3 free sessions this month" + "Upgrade" button if at limit
- Family overview card (when sessions exist): 3 mini stats — Sessions count / Total minutes / Proofs approved
- Today's Schedule card (when schedules exist): row per child — "ChildName - 60m" + "Start Now" button

**Child cards (per child):**
- Left: CircleAvatar with first letter + status dot (green=idle, orange=locked)
- Name 18pt bold
- Lock status text
- 2 action buttons: "Kid View" (outlined) + "Start Lock" / "View Lock" (filled)
- Button row 2: History | Stats | Schedule | Gallery | Profile

**Empty state:** "Add your first child to get started" + "Add Child" button

**FAB:** "Add Another Child"

---

## Screen 6: Lock Config Screen
**File:** `lock_config_screen.dart`

**Title:** "Lock — ChildName"

**Duration section:**
- "Minimum lock time" label
- SegmentedButton: 30m | 45m | 1h | 1.5h | 2h
- "Auto-lift after (optional)" label
- SegmentedButton: Never | 90m | 2h | 3h

**Approval Mode section:**
- SegmentedButton: Strict | Balanced | Parent Only
- Description text below selected mode

**Presets section (horizontal scroll):**
- Save Current as Preset button
- Chips showing saved presets with delete (X)

**Apps to Block section:**
- 4 checkboxes with icons:
  - Social Media (people icon) — TikTok, Instagram, Snapchat, Facebook, X, WhatsApp
  - Games (sports_esports icon) — Roblox, Minecraft, Fortnite, Call of Duty, Candy Crush
  - Entertainment (tv icon) — YouTube, Netflix, Hulu, Disney+, Twitch
  - All Distractions (block icon)
- Start button: "Lock N pack(s)" / "Start Homework Lock"

---

## Screen 7: Lock Active Screen (Parent)
**File:** `lock_active_screen.dart`

**AppBar:** "ChildName — Lock Active"
**Action:** "Unlock Early" text button

**Timer card:** SessionTimer widget — shows elapsed time, remaining, total duration
**Controls row:** Pause/Resume | Extend
**Break requests card** (when pending): "Child wants a break" + Allow / Deny buttons

**Proofs section:**
- "Approve All" button (when proofs pending)
- Each proof card:
  - Task description bold
  - AI decision badge (green/orange/red)
  - Parent decision badge
  - Photo thumbnail (tappable → full screen)
  - Parent note (if exists) with comment icon
  - Approve (filled) / Reject (outlined) buttons

**Empty state:** Hourglass icon + "Waiting for proof submissions..." + "Auto-refreshes every 10s"

---

## Screen 8: Kid Home Screen
**File:** `kid_home_screen.dart`

**Active lock:**
- Streak card (if streak > 0): ⭐ "N-day streak!" / 🔥 "Unstoppable!" at 7+
- SessionTimer widget
- Tasks card: "Tasks (X/Y)" with progress
  - Each task: radio button icon (pending=orange, done=green), description, subject tag, status, "Submit" button
- "Add Tasks" / "Submit Proof" buttons
- "All tasks submitted!" green card when done
- "Ask for a Break" outlined button
- "My History" outlined button

**No active lock:**
- Large green check_circle (56px)
- "No homework lock right now" 22pt bold
- "Enjoy your apps!" 16pt

---

## Screen 9: Task Entry Screen
**File:** `task_entry_screen.dart`

**AppBar:** "Today's Homework"

**Input row:** TextField "Add a task" + Add button (filled, + icon)
**Subject dropdown:** General | Math | Science | English | History | Foreign Language | Art | Music | Other

**Task list:** Cards with swipe-to-delete
- Radio icon (empty=orange, check=green)
- Description
- Subtitle: "Subject · Status: pending/submitted"
- Action: "Submit Proof" button (when pending) or "Retake" icon (when submitted)

**Empty state:** edit_note icon + "Add what you need to finish today" + "Type above and press +"

---

## Screen 10: Proof Capture Screen
**File:** `proof_capture_screen.dart`

**AppBar:** "Proof: Task Description"

**No photos yet:**
- Camera icon (48px) in circle
- "Take photos of your completed homework"
- "Take Photo" (filled) + "Choose from Gallery" (outlined)

**After taking photos:**
- 3-column grid of photo thumbnails
- Each has an X close button (delete)
- Last cell: "Add more" placeholder
- Note text field: "Note for parent (optional)"
- Submit button: "Submit X Photos" with upload icon

---

## Screen 11: Proof Image Viewer
**File:** `proof_image_viewer.dart`

**AppBar:** Task description as title
**If multiple photos:** "1/3" page counter in AppBar actions

**Photo area:** InteractiveViewer (pinch-zoom)
**If multiple:** PageView with dot indicators below
**AI result panel** (bottom, colored background):
- "AI: approved/rejected/needs_review" bold
- "Confidence: 87%"
- AI reason text
- Divider
- "Parent: approved/rejected" (if decided)
- Parent note with comment icon (if present)

---

## Screen 12: Proof Review Screen (Session History)
**File:** `proof_review_screen.dart`

**AppBar:** "Session History"
**Action:** Clear filters icon (when filters active)

**Search/Filter bar:**
- TextField with search icon — "Search by status..."
- Date range picker button — "Filter" or "M/D"

**Session list:** Cards with:
- Status icon (check=completed green, play=active orange)
- "status — YYYY-MM-DD"
- "Min: 60m | balanced"
- Arrow forward

**Tapping a session:** Proof list with cards showing:
- Photo thumbnail (tappable → viewer)
- Task description bold
- AI badge + Parent badge
- AI reason text
- Parent note with comment icon

**Empty state:** History icon + "No sessions found" + "Try adjusting your filters"

---

## Screen 13: Proof Gallery Screen
**File:** `proof_gallery_screen.dart`

**AppBar:** "ChildName's Proofs"

**3-column grid** of photo thumbnails:
- Colored border: green=approved, red=rejected, blue=AI approved, orange=pending
- Date overlay at bottom
- Check/cancel icon top-right (when parent decided)
- Photo count badge "1/3" when multiple
- Tap → ProofImageViewer

**Empty state:** photo_library icon + "No proof photos yet" + "Proofs appear here after submission"

---

## Screen 14: Session Stats Screen
**File:** `sessions_stats_screen.dart`

**AppBar:** "ChildName's Stats"

**Stat cards** (each with icon + label + value):
- Total Sessions (play_circle, primary)
- Total Study Time (timer, accent)
- Completed (check_circle, success)
- Cancelled (cancel, danger)
- Proofs Approved (verified, info)

**This Week chart:** 7-day bar chart (Mon-Sun) showing minutes per day
- Current day highlighted in primary, rest faded

**Completion Rate card:** LinearProgressIndicator + "XX% of sessions completed successfully"

---

## Screen 15: Schedules Screen
**File:** `schedules_screen.dart`

**AppBar:** "ChildName's Schedule"
**Action:** Add (+) button

**Schedule list:** Cards per day:
- Calendar icon (highlighted if today)
- Day name (Mon-Sun) bold
- "XX min | balanced" subtitle
- "Start Now" button (if today + no active lock)
- Delete icon (red)

**Add dialog:** 
- Day chips (Mon-Sun)
- Duration SegmentedButton (30m/1h/1.5h/2h)
- Mode SegmentedButton (Balanced/Strict)
- "Add" button

**Empty state:** calendar_month icon + "No recurring schedule" + "Add weekly homework routines"

---

## Screen 16: Kid Profile Screen
**File:** `kid_profile_screen.dart`

**AppBar:** "ChildName's Profile"

**Avatar preview:** Large circle (100px) with selected color background + emoji
**Name field:** TextField with person icon
**Color Theme picker:** 8 color circles (horizontal wrap)
**Avatar picker:** 8 emoji tiles (horizontal wrap, selected has colored border)

**Save button:** "Save Profile"

---

## Screen 17: Settings Screen
**File:** `settings_screen.dart`

**Sections:**

**Account:**
- Profile card: Avatar (first letter) + name + email + arrow → Edit dialog (name + family name)
- "DoneFirst Plus" card: "X free sessions/month" + "Upgrade" button
- "Co-Parent" → arrow to CoparentScreen
- "Set/Change Parent PIN" → arrow → 4-digit dialog
- "Change Password" → arrow → dialog (current, new, confirm)

**Notifications (local toggles):**
- Proof submitted (switch)
- Break requested (switch)
- Session complete (switch)

**Appearance:**
- Dark Mode (switch)

**Proof Verification:**
- Auto-approve math proofs (switch)

**Default Session:**
- Duration SegmentedButton: 30 min | 1 hour | 1.5 hr | 2 hr

**Danger Zone:**
- "Delete Account" (red) → confirmation dialog

---

## Screen 18: Notifications Center
**File:** `notification_center_screen.dart`

**AppBar:** "Notifications"
**Action:** "Mark all read" (when unread exist)

**List:** Cards per notification:
- Colored icon in circle: blue=camera_alt (proof), orange=coffee (break), green=coffee_outlined (break granted), green=check_circle (session)
- Title bold if unread
- Body text
- Blue dot indicator (unread)
- Tap → mark as read
- Swipe left → dismiss

**Empty state:** notifications_none icon + "No notifications" + "Activity appears here"

---

## Screen 19: Kid History Screen
**File:** `kid_history_screen.dart`

**AppBar:** "ChildName's History"

**Session list:** Cards with:
- Status icon (check/play/cancel) with colored circle bg
- Date bold
- Duration + status subtitle
- Arrow forward → proof viewer

**Proof viewer:** Same layout as parent's review but simplified — shows photo + task description + AI status badge

**Empty state:** History icon + "No sessions yet" + "Complete homework to see your history"

---

## Screen 20: Coparent Screen
**File:** `coparent_screen.dart`

**AppBar:** "Co-Parent"

**Invite section:**
- Email field
- "Send Invite" button
- Pending invites list with "Cancel"

**How it works text:** Explains co-parenting

---

## Screen 21: Upgrade Screen
**File:** `upgrade_screen.dart`

**Tier cards:**

**Free:** $0 — 3 sessions/month, Basic AI verification, 1 child
**Plus (highlighted/best value):** $4.99/mo — 30 sessions/month, Priority AI, 5 children, Schedules & streaks
**Pro:** $9.99/mo — Unlimited sessions, Advanced AI, Unlimited children, Co-parenting + Priority support

**Features comparison per tier**

---

## Screen 22: PIN Screen
**File:** `pin_screen.dart`

- 4-digit input (centered, large font, letter-spacing 8)
- Hidden dots (obscureText)
- Keypad or simple text input
- "Enter Parent PIN" prompt

---

## Screen 23: Co-Parent / Parent Invites

**Additional dialogs:**
- Invite dialog: email field + Send button
- Pending invites: list with Cancel
- Accept invite screen (from email link)

---

## Color Schemes

### Light Mode
| Element | Color |
|---------|-------|
| Background | `#F8F6FC` |
| Cards | `#FFFFFF` |
| AppBar | `#FFFFFF` |
| Text | `#1A1A2E` |
| Text Secondary | `#6B7280` |
| Border | `#E5E7EB` |

### Dark Mode
| Element | Color |
|---------|-------|
| Background | `#121212` |
| Cards | `#1E1E2E` |
| AppBar | `#1E1E2E` |
| Text | `#FFFFFF` |
| Text Secondary | `#9CA3AF` |
| Border | `#2D2D3A` |

---

## Component Specs

**Cards:** elevation 0, border 0.5px solid Border, radius 12
**Buttons:** height ~48px, radius 10, horizontal padding 24
**FilledButton:** Primary bg, white text, 16px semibold
**OutlinedButton:** Primary border/text, 16px semibold
**Chips:** ChoiceChip for day selection, InputChip for presets
**SegmentButtons:** Selected = primary with 10% opacity bg
**TextFields:** filled=true, fillColor white (light) / cardDark (dark), radius 10, primary focus border
**Dialogs:** Standard AlertDialog, title + content + Cancel/Save actions
**BottomSheet:** Standard modal with ListTiles
