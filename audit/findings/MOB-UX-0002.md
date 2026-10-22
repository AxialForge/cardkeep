---
finding_id: MOB-UX-0002
audit_domain: 06
platform: android
severity: S1
blockers: []
title: "Sync to desktop" is a live drawer entry that opens a "coming in 0.8" placeholder
status: fixed-verified
confidence: high
evidence_basis: runtime
affected_component: navigation drawer; Sync to desktop screen
affected_screen: Sync to desktop
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** The drawer lists "Sync to desktop" alongside working features. Tapping it opens a screen that only says "Sync to desktop is on the way - This part of the app arrives in version 0.8." Shipping unfinished features as navigable entries reads as broken to users, and Google Play's minimum functionality guidance discourages placeholder content. Low severity because it is clearly labelled and harmless.

**Steps to reproduce.** Drawer > Sync to desktop.
**Expected.** Entry hidden until the feature exists (or clearly marked "Coming soon" in the drawer itself).
**Observed.** Placeholder screen.

**Evidence.** `audit/artifact/screens/27_Sync_to_desktop.png`; UI dump of drawer: `Button Sync to desktop w=308 h=50` (`audit/artifact/screens/02_drawer.png`).

**Impact.** User: dead end. Business: minor store-review risk once on Play (placeholder features).
**Recommended remediation.** Hide the entry behind a feature flag until 0.8, or mark it "Coming soon" in the drawer.
**Verification procedure.** Drawer no longer shows the entry (or shows it marked).

**References.** Google Play "Minimum functionality" policy, checked 2026-10-21.

**Fix (batch C, 2026-10-22).** Sync to desktop removed from the drawer until built; drawer test asserts it is absent.

**Verification pass 2026-10-22 (Phase 22): fixed-verified [static].** drawer.dart: the /sync destination is removed until 0.8.
