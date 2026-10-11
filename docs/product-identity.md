# Peel — product identity & monetization (roadmap)

**Version:** 0.1.1  
**Date:** 2026-10-11  
**Status:** **Roadmap / product decision draft — not a description of current software**  
**Publisher:** [Snack Studio](https://snackstud.io)  
**Shipped truth:** [`SHIPPED.md`](SHIPPED.md) ← **read first**

This document records *where we want Peel to go* (one brand, free everyday unarchiving, optional Pro recovery).  
**It does not claim that create/compress, Quick Look product, MCP, PeelFS mounts, or Pro recovery exist in HEAD.**

---

## 0. Shipped vs this doc (mandatory)

| In HEAD today (see SHIPPED.md) | In this doc (roadmap) |
| --- | --- |
| Extract multi-format via peel-core + CLI | Create/compress writers |
| macOS app, Services, HUD, browse-on-open fallback | Full in-app archive browser as primary surface |
| PeelFS **extension scaffold**; mount often OS-blocked | Qualified read-only Finder mount |
| QL **scaffold** only | Polished Finder Quick Look |
| — | MCP tools |
| — | Peel Pro / forgotten-password recovery |
| — | Encryption create / migrate product flows |

If you are implementing or evaluating, **do not** treat sections 2–8 as done work.

---

## 1. Product decision: one Peel

**Peel is one product, one brand, and one integrated experience.** Do not create separate branded Extract, Explore, or Protect apps.  
Positioning: **Peel — Open what's inside.**

**Brand invariants (intent):** one icon, one name, one settings system, one capability model, one job model.  
**Pro** (if ever shipped) is an entitlement inside Peel, not a second app. No upsells on routine extract or known-password unlock.

---

## 2. Core free experience (**target**, not HEAD)

*When qualified in code and listed in SHIPPED.md*, free Peel should include:

- Detect, list, extract, selective extract, verify for supported formats  
- Create/compress and encrypted create (**not shipped**)  
- Known-password unlock with a secure prompt (**partial engine paths; not a finished product flow**)  
- Finder Quick Look + optional PeelFS browse (**scaffold / blocked — not qualified**)  
- Clear failures, budgets, cancel, staging, receipts (**partial**)

Publish support by **format × operation × platform**, only after qualification.

---

## 3. Peel Pro: forgotten-access recovery (**proposal only**)

**Not implemented.** No Pro entitlement, no recovery UI, no candidate engine.

**Intended value (if built):** help users recover access to *their own* archives when normal unlock fails — local-first, authorized, evidence-based.  
**Not:** universal crypto break, AES defeat, or paywall on ordinary password entry.

Candidate ideas (research required before any ticket is “done”): guided password reconstruction, consent-based key discovery, budgeted local testing, narrow legacy methods with fixtures, honest feasibility preflight **before** paywall.

Commercial hypothesis (not a decision): one-time ~US$29–49; must not promise successful unlock.

---

## 4. Capability matrix (**targets only**)

| Capability | Free target | Pro target | In HEAD? |
| --- | --- | --- | --- |
| Extract supported archives | Yes | Yes | **Yes (core path)** |
| Browse-on-open / folder-like open | Yes | Yes | **Partial** (cache fallback; FSKit often disabled) |
| Create/compress | Yes | Yes | **No** |
| Finder Quick Look | Yes | Yes | **Scaffold only** |
| PeelFS mount | Yes | Yes | **Scaffold; mount blocked** |
| MCP / agent server | Yes (if ever) | — | **No** |
| Known-password unlock UX | Yes | Yes | **Partial** |
| Forgotten-password recovery | Preflight free | Engine Pro | **No** |
| Encryption create/migrate | Yes | Yes | **No** |

---

## 5. User journeys (**intended**; mark blockers)

### A. Ordinary archive
**Intent:** Space preview → browse or extract → no paywall.  
**HEAD:** Double-click browse-on-open (fallback volume); Services extract; QL not qualified.

### B. Encrypted, known password  
**Intent:** secure prompt → extract/browse.  
**HEAD:** engine password hooks exist in places; not a finished end-to-end product story.

### C–D. Forgotten password / legacy crypto / Pro  
**Roadmap only.**

### E. Archive as Finder folder  
**Intent:** PeelFS read-only mount.  
**HEAD:** try mount, else materialize browse cache; see `finder-open-interaction.md`.

---

## 6. Architecture (target sketch)

```text
Finder / QL / SwiftUI / CLI
        → Operation API → peel-core
        → (future) recovery planner [Pro]
```

Entitlements would gate **recovery**, not parsers or ordinary extract.  
Do not fork Free/Pro engines.

---

## 7. Delivery stages (roadmap)

| Stage | Work | Note |
| --- | --- | --- |
| 0 Safety | budgets, cancel, staging, no secret leakage | in progress / ongoing |
| 1 Everyday extract + honest open | browse fallback, Services, CLI | **primary HEAD focus** |
| 2 Finder | QL qualify, PeelFS Gate A, XPC bridge | scaffold + docs |
| 3 Protection audit | inspect/migrate | not started as product |
| 4–5 Pro recovery | only after free everyday is solid | not started |

---

## 8. Tickets (product)

Track on GitHub: [SnackStudio/peel](https://github.com/SnackStudio/peel) epics #1–#5.  
PRD-style items below remain **backlog ideas**, not completed work.

- PRD-001 one-product brand  
- PRD-002 Free/Pro boundary at recovery only  
- PRD-003–008 recovery/QL/pricing — **future**

---

## 9. Decision summary

**One Peel.** Everyday extract/open must stay excellent and free.  
Pro recovery is a **possible** paid wedge, not a current codebase feature.  
Finder-native open is a **core goal**; implementation today is browse-cache + blocked FSKit, not a finished mount product.

**Always sync claims with [`SHIPPED.md`](SHIPPED.md).**
