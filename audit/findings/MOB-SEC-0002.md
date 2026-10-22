---
finding_id: MOB-SEC-0002
audit_domain: 12
platform: android
severity: S1
blockers: []
title: "Follow-up reminders show the contact's name, company and event on the lock screen (no visibility or publicVersion set)"
status: fixed-verified
confidence: high
evidence_basis: static
affected_component: "lib/core/followups/reminders.dart:65-80"
affected_version: "0.6.0 (2010) cdcf49d"
description: "zonedSchedule uses the title 'Follow up with <name>' and the body '<company> · met at <event>', with AndroidNotificationDetails that set no visibility or publicVersion. With the default lock-screen setting (show all content) the full text is readable without unlocking. Low impact: the user set the reminder and can change the system lock-screen setting. The payload is only the person id, and a tap only opens the contact screen in-app."
expected_behavior: "The lock-screen version is generic (for example 'Follow-up reminder'), via NotificationVisibility.private plus a public version, or a setting."
observed_behavior: "Full PII text in the notification with default visibility."
evidence:
  - "lib/core/followups/reminders.dart:67-68 title and body built from f.name, f.company, f.eventName"
  - "lib/core/followups/reminders.dart:71-77 AndroidNotificationDetails without a visibility parameter"
  - "lib/core/followups/reminders.dart:80 payload: f.personId (no PII in the payload)"
impact:
  privacy: "Contact name and company readable by anyone who sees the locked phone."
recommended_remediation: "Set visibility: NotificationVisibility.private with a generic public title, or offer a 'hide names on lock screen' setting."
verification_procedure: "Schedule a reminder on the emulator, lock the screen, and confirm the lock-screen text is generic."
references:
  owasp_masvs: [MASVS-PLATFORM-3, MASVS-PRIVACY-1]
  owasp_maswe: [MASWE-0054]
  other: [CWE-359]
---

## Fix

Follow-up notifications use NotificationVisibility.private: the lock screen shows only that CardKeep has a notification.

**Verification pass 2026-10-22 (Phase 22): fixed-verified [static].** reminders.dart: NotificationVisibility.private on follow-up notifications. Lock-screen check on a device not run.
