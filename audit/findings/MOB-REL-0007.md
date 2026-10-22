---
finding_id: MOB-REL-0007
audit_domain: 11
platform: android
severity: S1
blockers: []
title: Reminder sync calls cancelAll, which also clears today's reminder already shown; ids come from String.hashCode
status: fixed (unverified)
confidence: medium
evidence_basis: static
affected_component: lib/core/followups/reminders.dart:52 and 62
affected_screen: Notifications, Follow-ups
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** `sync` calls `_plugin.cancelAll()` and then re-schedules only follow-ups dated in the future. On Android, `cancelAll` also removes notifications that are already showing. A reminder that fired at 08:00 today therefore vanishes the next time `sync` runs, which is on app start or any follow-up edit, before the user has acted on it.

Ids are `personId.hashCode & 0x3fffffff`. The Dart VM computes string hash codes deterministically, so the ids are stable. Two people can still collide, in which case one reminder replaces the other. The chance is about n^2/2^31, roughly 0.05% with 1,000 open follow-ups. That is low, but nothing guards against it.

**Remediation.**
- Diff against `pendingNotificationRequests()` and cancel only ids that are no longer wanted.
- Assign ids from a stored counter instead of from hashCode.

**Verification.** Fake-plugin test: re-syncing an unchanged list cancels nothing.

**Fix (batch C, 2026-10-22).** Ids are FNV-1a of the uuid; sync cancels only pending reminders no longer wanted (no cancelAll). Tested ids.
