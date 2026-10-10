# HUD cancel / layout fix

## Bug
Closing the quick extract popup reopened it. Progress timer called `update()` which re-`show()`ed panels for still-running jobs after dismiss.

Also stuck ~89–90%: fake progress hard-capped at 0.9 while extract continued.

## Fix
- `ProgressPanelController` tracks `dismissed` job IDs — never reopens after X.
- Borderless HUD (no traffic lights), bottom-right of mouse screen, tighter layout.
- X = cancel: kills peel engine process via `PeelClient.cancelActive()`, marks job `.cancelled`.
- Progress eases asymptotically toward 95% (time-based); large archives skip pre-list.
- Installed `/Applications/Peel.app`.
