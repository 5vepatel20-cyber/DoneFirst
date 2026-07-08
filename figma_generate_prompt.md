# DoneFirst Figma Generation Prompts

Use these prompts with any MCP client connected to the Figma Remote MCP server.

## Step 1: Create the file

```
Create a new Figma Design file called "DoneFirst" and add a page called "Screens". 
Set the frame size to iPhone 14 Pro (393 x 852).
```

## Step 2: Create design system variables

```
In the "DoneFirst" file, create these local variables:
- Colors/Primary: #6C3FC5
- Colors/PrimaryLight: #9B7FD4
- Colors/Accent: #FF8C42
- Colors/Success: #2ECC71
- Colors/Danger: #E74C3C
- Colors/Warning: #F39C12
- Colors/Info: #3498DB
- Colors/Surface: #F8F6FC
- Colors/CardLight: #FFFFFF
- Colors/CardDark: #1E1E2E
- Colors/TextPrimary: #1A1A2E
- Colors/TextSecondary: #6B7280
- Colors/Border: #E5E7EB
- Colors/DarkBG: #121212
- Radius/Small: 8
- Radius/Medium: 10
- Radius/Large: 12
- Spacing/Unit: 8
```

## Step 3: Generate each screen

Copy and paste **one** of these at a time into your MCP client:

### Screen 1: Auth Screen
```
In the "Screens" page, create a frame called "01 - Auth" at iPhone 14 Pro size (393x852) with these elements:
1. Center: A circle (60x60) with fill #6C3FC5 containing a check_circle_outline icon, centered horizontally at y=160
2. Text "DoneFirst" 28pt bold, color #1A1A2E, centered, y=240
3. Text "Homework first. Apps after." 15pt, color #6B7280, centered, y=275
4. TextField for email at y=340, width=340, height=50, radius=10, placeholder "Email", prefix icon = email icon
5. TextField for password at y=405, width=340, height=50, radius=10, placeholder "Password", prefix icon = lock icon, suffix text "6+ chars"
6. FilledButton "Sign Up" at y=480, width=340, height=50, radius=10, fill #6C3FC5, white text 16pt semibold
7. TextButton "Forgot password?" at y=540, 14pt, color #6C3FC5
8. Text "New? Create an account" 14pt at y=580, color #6B7280 with "Create an account" in #6C3FC5
```

### Screen 4: Onboarding Page 1
```
In the "Screens" page, create a frame called "04 - Onboarding 1" at 393x852:
1. Phone illustration placeholder centered at y=200 (SVG of a phone with checkmark)
2. Text "Homework First" 26pt bold, centered at y=480, color #1A1A2E
3. Text "Set homework time, block distractions" 16pt, color #6B7280, centered, y=520
4. 4 dot indicators at y=680, centered, first dot fill #6C3FC5, rest fill #E5E7EB
5. "Skip" text button at top-right, 14pt, color #6B7280
6. "Next" button at bottom-right, 16pt, color #6C3FC5
```

### Screen 7: Parent Dashboard
```
In the "Screens" page, create a frame called "02 - Parent Dashboard" at 393x852:
1. AppBar: Header "DoneFirst" 22pt bold with check_circle_outline icon, action icons: refresh, bell (with badge "2"), settings gear, sign out
2. Stats card: white card with radius 12, y=100, h=80, containing: row of 3 stat blocks — "12 Sessions" / "840 min" / "85% approved"
3. Child card: white card with radius 12, y=200, h=160, containing:
   - CircleAvatar with letter "A", fill #6C3FC5, white text 20pt
   - Name "Alex" 18pt bold
   - Status dot (green, 10px) + "Idle" text
   - OutlinedButton "Kid View" + FilledButton "Start Lock" (fill #6C3FC5)
   - Row of 5 links: History | Stats | Schedule | Gallery | Profile (each 11pt, #6C3FC5)
4. FAB at bottom-right: "+" icon, circle 56px, fill #6C3FC5
```

### Screen 8: Lock Config
```
In the "Screens" page, create a frame called "03 - Lock Config" at 393x852:
1. AppBar: "Lock — Alex", back arrow
2. Section: "Duration" label 13pt secondary, SegmentedButton with: 30m | 45m | 1h | 1.5h | 2h
3. Section: "Auto-lift after" label, SegmentedButton: Never | 90m | 2h | 3h
4. Section: "Approval Mode" SegmentedButton: Strict | Balanced | Parent Only
5. Section: "Presets" horizontal scroll of chips
6. Section: "Apps to Block" with 4 checkboxes:
   - Social Media (people icon): TikTok, Instagram, Snapchat, Facebook, X, WhatsApp
   - Games (sports_esports): Roblox, Minecraft, Fortnite, COD, Candy Crush
   - Entertainment (tv): YouTube, Netflix, Hulu, Disney+, Twitch
   - All Distractions (block)
7. FilledButton at bottom: "Lock 1 pack", fill #6C3FC5, white text, full width
```

### Screen 9: Lock Active (Parent)
```
In the "Screens" page, create a frame called "04 - Lock Active" at 393x852:
1. AppBar: "Alex — Lock Active", "Unlock Early" text button right
2. Timer card: white card, radius 12, y=100, containing:
   - Circular timer display with elapsed time "25:00" bold 36pt
   - "of 60:00" secondary text
   - Row: Pause button | Extend +15 button | Extend +30 button
3. If break requested: orange warning card "Alex wants a break" with Allow | Deny buttons
4. Proof section header: "Proofs" + "Approve All" button
5. Proof card: white card with:
   - Photo thumbnail 80x80, radius 8
   - Task name bold
   - AI status badge (green "AI: approved" / orange "pending")
   - Parent note text with comment icon
   - Approve button (filled, #2ECC71) | Reject button (outlined, #E74C3C)
6. If no proofs: hourglass icon + "Waiting for proof submissions..."
```

### Screen 11: Kid Home
```
In the "Screens" page, create frame "05 - Kid Home" at 393x852:
1. Streak card (if streak > 0): orange/red gradient, radius 12, h=60, text "⭐ 5-day streak!"
2. Timer card: elapsed "00:12:34", "#6C3FC5" circle border
3. Tasks card: "Tasks (2/3)" with 3 task rows:
   - Radio button circle (orange for pending, green for done)
   - Task description, subject tag chip, status text
   - "Submit" button for pending tasks
4. Buttons: "Add Tasks" (filled, #6C3FC5) | "Submit Proof" (filled, accent #FF8C42) | "Ask for Break" (outlined) | "My History" (outlined)
```

### Screen 13: Task Entry
```
In the "Screens" page, create frame "06 - Task Entry" at 393x852:
1. AppBar: "Today's Homework"
2. Input row: TextField (flex) + Add icon button (filled circle, #6C3FC5)
3. Subject dropdown: Math | Science | English | History | etc.
4. Task card row: radio circle icon, "Complete math worksheet" text, "Math" chip (blue bg), "Submit Proof" button
5. If no tasks: edit_note icon centered + "Add what you need to finish today"
```

### Screen 14: Proof Capture
```
Create frame "07 - Proof Capture" at 393x852:
1. AppBar: "Proof: Complete math worksheet"
2. No photos: camera icon in circle (48px), "Take photos of completed work", "Take Photo" button + "Choose from Gallery" button
3. Has photos: 3-column grid of thumbnails with X delete buttons, last cell add-more placeholder
4. Note field: "Note for parent (optional)"
5. Submit button: "Submit 3 Photos" with upload icon, fill #6C3FC5
```

### Screen 15: Proof Image Viewer
```
Create frame "08 - Proof Viewer" at 393x852:
1. AppBar: task description title, page "1/3" count right
2. Photo: full-width image with pinch-zoom indicator
3. Dot indicators: 3 dots (first filled #6C3FC5, rest #E5E7EB)
4. Bottom panel (colored bg by status):
   - "AI: approved" bold, confidence "87%"
   - AI reason text
   - Divider
   - "Parent: approved" (if decided)
   - Parent note with comment icon
```

### Screen 16: Session Stats
```
Create frame "09 - Stats" at 393x852:
1. AppBar: "Alex's Stats"
2. 5 stat cards in a row or 2-row grid:
   - "12" + "Sessions" icon play_circle
   - "840" + "Minutes" icon timer
   - "10" + "Completed" icon check_circle  
   - "2" + "Cancelled" icon cancel
   - "10" + "Approved" icon verified
3. Bar chart: "This Week", 7 bars (Mon-Sun), today bar highlighted #6C3FC5, rest faded
4. Card: "Completion Rate" + progress bar + "83%"
```

### Screen 17: Proof Gallery
```
Create frame "10 - Proof Gallery" at 393x852:
1. AppBar: "Alex's Proofs"
2. 3-column grid of photo thumbnails with colored borders:
   - Green border = approved by parent
   - Red border = rejected by parent  
   - Blue border = AI approved
   - Orange border = pending
   - Date overlay bottom
   - Badge "1/3" when multiple
   - Check/cancel icon top-right
```

### Screen 18: Schedules
```
Create frame "11 - Schedules" at 393x852:
1. AppBar: "Alex's Schedule", + icon action
2. Schedule cards per day: calendar icon, "Mon" bold, "60 min | balanced", "Start Now" button (today only), delete icon
3. No schedules: calendar_month icon + "No recurring schedule"
4. Add dialog (overlay): day chips (Mon-Sun), duration 30m/1h/1.5h/2h, mode Balanced/Strict, "Add" button
```

### Screen 19: Kid Profile
```
Create frame "12 - Kid Profile" at 393x852:
1. AppBar: "Alex's Profile"
2. Avatar preview: 100px circle, color fill, emoji "🚀" 40pt
3. Name field with person icon
4. Color theme: 8 color circles (horizontal wrap)
5. Avatar: 8 emoji tiles (horizontal wrap), selected has #6C3FC5 border
6. Save button: "Save Profile", fill #6C3FC5
```

### Screen 20: Settings
```
Create frame "13 - Settings" at 393x852:
1. AppBar: "Settings"
2. Account section: profile card (avatar + name + email + arrow), "DoneFirst Plus" card with session count, "Co-Parent", "Set Parent PIN", "Change Password"
3. Notifications section: "Proof submitted" toggle, "Break requested" toggle, "Session complete" toggle
4. Appearance: "Dark Mode" toggle
5. Proof Verification: "Auto-approve math proofs" toggle
6. Default Session: duration segmented control 30min/1h/1.5h/2h
7. Danger zone: "Delete Account" red button
```

### Screen 21: Notification Center
```
Create frame "14 - Notifications" at 393x852:
1. AppBar: "Notifications", action "Mark all read"
2. List of notification cards with:
   - Colored icon circle (blue camera_alt = proof, orange coffee = break, green = complete)
   - Title bold (if unread)
   - Body text
   - Blue dot (unread indicator)
   - Time subtitle
3. Empty state: notifications_none icon + "No notifications"
```

### Screen 22: Kid History
```
Create frame "15 - Kid History" at 393x852:
1. AppBar: "Alex's History"
2. Session list with colored status icons:
   - Green check circle = completed
   - Orange play circle = active  
   - Red cancel = cancelled
   - Date bold, duration subtitle, arrow forward
3. Empty: History icon + "No sessions yet"
```

### Screen 23: Coparent
```
Create frame "16 - Co-Parent" at 393x852:
1. AppBar: "Co-Parent"
2. Email field: "Email" placeholder
3. "Send Invite" button, fill #6C3FC5
4. Pending invites list with cancel
5. "How it works" text section
```

### Screen 24: Upgrade
```
Create frame "17 - Upgrade" at 393x852:
1. AppBar: "Upgrade Plan"
2. Free card: $0, 3 sessions/mo, Basic AI, 1 child, white card with border
3. Plus card (highlighted): $4.99/mo, 30 sessions, Priority AI, 5 children, Schedules & streaks, primary bg section
4. Pro card: $9.99/mo, Unlimited, Advanced AI, Unlimited, Co-parenting
5. Features table: checkmarks per tier
```

### Screen 25: PIN
```
Create frame "18 - PIN" at 393x852:
1. Center content at y=300
2. Text "Enter Parent PIN" 20pt bold
3. 4 dash characters with letter-spacing 8, large 36pt font, obscureText circles
```

### Screen 26: Verify Email
```
Create frame "19 - Verify Email" at 393x852:
1. Center accent circle: mark_email_unread icon, 48px, #FF8C42
2. "Verify your email" 24pt bold
3. "We sent a verification link to\nalex@email.com" 15pt secondary
4. "Click the link in the email, then come back." 13pt secondary
5. "I've Verified — Continue" filled button #6C3FC5
6. "Resend Email" outlined button
7. "Skip — I'll verify later" text, secondary color
```

### Screen 27: Lock Active (dark mode)
```
Create frame "20 - Lock Active (dark)" at 393x852:
Same as Screen 9 but with dark background #121212, cards #1E1E2E, text white, borders #2D2D3A.
```

---

## Quick batch prompt (use with caution — may hit rate limits)

```
In the "DoneFirst" file, on the "Screens" page, create all these frames at 393x852:
"01 - Auth" with centered purple icon, "DoneFirst" heading, email/password fields, Sign Up button
"02 - Parent Dashboard" with app bar, stats card, child card with avatar/status/buttons
"03 - Lock Config" with duration selectors, app pack checkboxes
"04 - Lock Active" with timer, pause/extend, proof cards with approve/reject
"05 - Kid Home" with streak, timer, tasks list
"06 - Task Entry" with add task input, subject dropdown, task list
"07 - Proof Capture" with camera icon, photo grid, submit button
"08 - Proof Viewer" with photo, AI result panel
"09 - Stats" with stat cards and bar chart
"10 - Proof Gallery" with 3-column photo grid
"11 - Schedules" with day cards
"12 - Kid Profile" with avatar picker
"13 - Settings" with all sections
"14 - Notifications" with notification list
"15 - Kid History" with session list
"16 - Co-Parent" with invite form
"17 - Upgrade" with pricing cards
"18 - PIN" with 4-dash input
"19 - Verify Email" with verification message

Use the design system colors: Primary=#6C3FC5, Accent=#FF8C42, Success=#2ECC71, Danger=#E74C3C, Warning=#F39C12, Info=#3498DB
Surface=#F8F6FC for backgrounds, #FFFFFF for cards, #1A1A2E for text, #6B7280 for secondary, #E5E7EB for borders.
Typography: bold for headings, 15-16pt for body, 11-13pt for captions.
Radius: 12 for cards, 10 for buttons, 8 for small elements.
```

### Step 4: Apply auto-layout

```
For all frames in the "Screens" page, apply auto-layout with vertical direction, 8px padding, 
and 8px gap between sibling elements.
```
