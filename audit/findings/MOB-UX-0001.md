---
finding_id: MOB-UX-0001
audit_domain: 07
platform: android
severity: S2
blockers: []
title: Drawer destinations pile up on the back stack; Back walks through every section visited before leaving the app
status: fixed (unverified)
confidence: high
evidence_basis: runtime
affected_component: drawer navigation (go_router push vs go), lib/app/
affected_screen: Navigation drawer, all top-level sections
affected_version: 0.6.0 (2010) cdcf49d
---

**Description.** Opening top-level sections from the navigation drawer pushes each one onto the stack instead of replacing the current section. After visiting Events, Career moves, Review queue, Follow-ups, Duplicates, Tags (and others) via the drawer, system Back steps through each of them in reverse before reaching Contacts and exiting. Some entries (Export and backup, My card, Settings) did not stay on the stack, so the behaviour is also inconsistent between drawer items. Android's navigation principle is that top-level destinations reached from a drawer are siblings: Back from any of them goes to the start destination.

**Steps to reproduce.** 1. From Contacts open the drawer and visit Events, Career moves, Review queue, Follow-ups, Duplicates, Tags, Export and backup, Settings, Tap cards in turn. 2. Press Back repeatedly.

**Expected.** Back from a top-level section returns to Contacts; next Back leaves the app.
**Observed.** 8 Back presses needed:
```
1 : MainActivity | Tags
2 : MainActivity | Check the whole library again   (Duplicates)
3 : MainActivity | Follow-ups
4 : MainActivity | Scan cards                      (Review queue)
5 : MainActivity | Career moves
6 : MainActivity | Events
7 : MainActivity | Add contact                     (Contacts)
8 : NexusLauncherActivity                          (app left)
```

**Evidence.** Command output above (adb `input keyevent BACK` + `dumpsys window mCurrentFocus` + UI dump per step). Screens: `audit/artifact/screens/20_Events.png` .. `30_Tap_cards_NFC.png`.

**Impact.** User: confusing, "stuck in the app" feel; growing stack also keeps every visited screen alive in memory.
**Recommended remediation.** Use `context.go()` (replace) for drawer destinations, `push` only for detail/sub screens; make all drawer items consistent.
**Verification procedure.** Repeat the steps; Back from any drawer section lands on Contacts, then exits.

**References.** Android "Principles of navigation" (fixed start destination; Back to start from top-level), checked 2026-10-21.

**Fix (batch C, 2026-10-22).** Drawer goes to Contacts then pushes the section (lib/app/drawer.dart), so Back from any section returns to Contacts, then leaves.
