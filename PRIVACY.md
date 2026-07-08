# Privacy Policy — DoneFirst

**Last updated:** 2026-07-08
**Status:** Draft — not legal advice. Have a lawyer review before any
public release that targets children.

## 1. Who we are

DoneFirst is a homework-accountability app for families. The service is
provided by an individual developer (the "DoneFirst team"). For privacy
questions, see the Contact section at the bottom of this policy.

## 2. What we collect

**Account data**
- Parent email address (used for sign-in and account recovery)
- Parent display name (chosen by the parent)
- Family name (chosen by the parent)

**Child data**
- Child name (entered by the parent)
- Avatar preferences: color and emoji (parent-selected)
- Streak metadata: streak count, last streak date

**Homework session data**
- Start and end times for each lock session
- Tasks entered by children (description, subject tag)
- Parent configuration: minimum lock minutes, maximum lift minutes,
  approval mode (auto / balanced / strict)
- Break requests: timestamp and approval status

**Proof data**
- Homework photos uploaded as verification (stored in a private Supabase
  bucket; URLs are signed with a 7-day expiry)
- Optional kid note attached to the proof
- Parent approval/rejection and any parent note
- AI verifier decision, confidence, and reasoning

**Usage metadata**
- Per-parent daily count of calls to the AI verifier (kept in
  `mistral_verification_log`, used to enforce a daily cap and shown to
  the parent in-app)

We do **not** collect: device identifiers for advertising, precise
location, contacts, microphone or camera recordings (camera is used only
at the moment of proof capture and the resulting photo is the only thing
stored), payment information, or any data from third-party apps.

## 3. How we use the data

- To run the lock session, task entry, and proof review flow.
- To verify homework via our AI verifier (see §4 for the data flow).
- To compute streaks and trigger milestone celebrations.
- To deliver in-app notifications (proof submitted, break requested,
  session complete).
- To enforce the daily AI verification cap (see §4).

We do **not** sell your data. We do **not** serve ads. We do **not** use
your data to train AI models.

## 4. Third-party services and data flow

**Supabase** (database, authentication, file storage, serverless functions)
- All persistent data is stored in a Supabase Postgres database and a
  Supabase Storage bucket. Supabase is a data processor; their privacy
  policy applies to data they handle on our behalf.
- Row Level Security policies (`rls_policies.sql` in our repository)
  restrict every table so that a parent can only access their own
  family's records.
- The `proof-photos` storage bucket is private. Photos are accessed via
  signed URLs that expire after 7 days; public URLs are not used.

**Mistral AI** (homework verification)
- When a child submits a proof photo, the photo's signed URL is sent
  through a Supabase Edge Function (`verify-proof`) to Mistral's
  chat-completions API. Mistral processes the image and returns a
  decision ("approved" / "needs_review" / "rejected"), a confidence
  score, and a brief reason. The image is **not** base64-encoded in the
  client; only the URL is sent to Mistral.
- A daily cap (default 50 calls per parent per 24 hours) is enforced by
  the Edge Function to prevent quota theft and runaway costs.
- Mistral's retention and processing of uploaded images is governed by
  Mistral's own privacy policy. We do not store images on Mistral's
  servers beyond the verification call.

**Anthropic / OpenAI** — we do not currently send any data to these
providers.

## 5. Children's privacy (COPPA / GDPR-K)

DoneFirst is intended to be set up by a parent or legal guardian, for a
child the parent or guardian is responsible for. We do not direct the app
to children under 13 to provide a service; the parent is the customer.

- Account creation requires the adult creating the account to confirm
  they are 18 or older and a parent or legal guardian (COPPA-style
  affirmative confirmation in the sign-up flow).
- The parent controls all child data: profile, photos, sessions, and
  history are visible only to the parent account that registered the
  child.
- Parents can delete child data at any time from the child profile
  screen, or delete the entire account and all associated family data
  from Settings → Delete Account.
- We do not show advertising to children. We do not use child data for
  profiling. We do not make child profiles publicly searchable.

If you believe a child has been added to DoneFirst without parental
consent, contact us at the address below and we will delete the record.

## 6. Data retention

- Account, child, session, and proof data is retained until the parent
  deletes the account, at which point all related records are deleted in
  a single cascade (children → sessions → proofs/tasks/breaks →
  schedules → family → parent → auth user).
- Proof photos are stored in the private bucket until the parent deletes
  the proof, the task, the session, or the account. Bucket objects are
  not automatically purged on the 7-day signed-URL expiry; the parent
  must delete them explicitly (or delete the account).
- The `mistral_verification_log` table retains one row per successful
  verification for 30 days, then is purged by a scheduled cleanup job
  (not yet implemented — see Launch Checklist).

## 7. Your rights

- **Access** — every record we store about your family is visible to you
  inside the app.
- **Correction** — profile, family name, child profile can be edited
  in-app at any time.
- **Deletion** — Settings → Delete Account removes the account and
  cascades to every related record in the family.
- **Export** — a data export feature is planned (see Launch Checklist).

## 8. Security

- Row Level Security is enabled and enforced on every owned-data table.
- The Mistral API key is stored in Supabase Edge Function environment
  variables, never in the client app.
- The Edge Function requires a valid Supabase access token and enforces
  a daily call cap per parent.
- Storage of proof photos uses a private bucket with signed URLs that
  expire after 7 days.

No system is perfectly secure. If you discover a security issue, please
report it via GitHub Issues marked "security" rather than disclosing
publicly until we have had a chance to respond.

## 9. Changes to this policy

We may update this policy. The "last updated" date at the top will
reflect the change. For material changes that affect existing users, we
will show an in-app notice and require acknowledgement before continued
use.

## 10. Contact

- Repository: `github.com/5vepatel20-cyber/DoneFirst`
- Issues: `github.com/5vepatel20-cyber/DoneFirst/issues`
- For security disclosures, please mark the issue "security".
- Privacy email (placeholder): `donefirst.support@example.com`
