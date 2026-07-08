/// Policy text for in-app display.
///
/// The canonical sources of truth are PRIVACY.md and TERMS.md at the repo
/// root. These constants mirror those documents so the app can show them
/// in a dialog without needing network access, url_launcher, or asset
/// bundling. Keep them in sync when either .md file changes.
///
/// TODO(blocker-5): These are placeholder drafts. Replace with the
/// legally-reviewed versions before any public release that targets
/// children. See DEVELOPER_HANDOFF.md "Blocker #5".
library;

const String kPrivacyPolicyText = '''
DoneFirst — Privacy Policy

Last updated: 2026-07-08

DoneFirst is a homework-accountability app for families. This policy
explains what data we collect, how we use it, and the choices you have.

1. Information we collect
   - Account: email, display name, family name.
   - Children: name, optional avatar/emoji/color, streak metadata.
   - Homework sessions: start/end times, durations, tasks, and parent
     configuration (min lock, max lift, approval mode).
   - Proof images: photos you submit as homework verification, stored
     in a private Supabase bucket; URLs are signed (7-day expiry).
   - Verification: AI decisions and confidence from Mistral, plus any
     parent override and note.

2. How we use information
   - To run the lock/approve flow, count streaks, and notify parents.
   - To verify homework via our AI verifier (proof images are sent to
     Mistral for the single purpose of returning a decision; Mistral
     retains data per its own policy).
   - We do not sell your data. We do not serve ads.

3. Children's privacy (COPPA / GDPR-K)
   - DoneFirst is intended to be set up by a parent or legal guardian
     for a child. We do not direct the app to children under 13.
   - Account creation requires the adult to confirm they are 18+.
   - Parents control all data and can delete the account and all
     associated child data at any time from Settings.

4. Storage and security
   - Data is stored in Supabase (Postgres + Storage). Access is
     protected by row-level security policies (see rls_policies.sql).
   - Storage bucket "proof-photos" is private; only signed URLs are
     issued, and they expire after 7 days.
   - Mistral API key is held server-side in a Supabase Edge Function
     and is never present in the client app.

5. Your rights
   - Access: the app shows you everything we store about your family.
   - Correction: edit profile, child profile, and family name in-app.
   - Deletion: Settings → Delete Account removes the account, family,
     children, sessions, tasks, proofs, breaks, schedules, and presets
     in a single cascade.

6. Contact
   - For privacy questions, contact the developer via the repository
     issue tracker: github.com/5vepatel20-cyber/DoneFirst/issues.

This is a draft and is not legal advice. Have it reviewed by counsel
before relying on it for any real release.
''';

const String kTermsOfServiceText = '''
DoneFirst — Terms of Service

Last updated: 2026-07-08

By using DoneFirst you agree to the following.

1. Eligibility
   - You must be 18 or older and a parent or legal guardian to create
     an account. You accept responsibility for the children you add.

2. Acceptable use
   - Use the app to support your child's homework routine.
   - Do not upload images that are illegal, harmful, or unrelated to
     homework verification.

3. AI verification
   - Proofs are reviewed by an AI model (Mistral). The decision is a
     suggestion; the final approval is yours.
   - The AI may be wrong. You can always override its decision.

4. No warranty
   - The app is provided "as is" without warranties of any kind.
   - We are not liable for any loss arising from reliance on the
     app's lock, AI decisions, or notifications.

5. Account termination
   - You may delete your account at any time from Settings.
   - We may suspend accounts that violate these terms.

6. Changes
   - We may update these terms. Continued use means acceptance of
     the updated terms.

7. Contact
   - For questions, file an issue at
     github.com/5vepatel20-cyber/DoneFirst/issues.

This is a draft and is not legal advice. Have it reviewed by counsel
before relying on it for any real release.
''';
