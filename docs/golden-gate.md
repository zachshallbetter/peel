# Golden Gate — Peel visual system

**Publisher:** [Snack Studio](https://snackstud.io)  
**Status:** Shipping in macOS app (SwiftUI materials)

Golden Gate is Peel’s liquid-glass UI language for macOS: system materials (`.ultraThinMaterial` / `.thinMaterial`), continuous corners, soft bay fog washes, orange peel accent, and transparent titlebars.

| Surface | Treatment |
| --- | --- |
| Main window | Full-size content view, clear chrome, fog gradient backdrop |
| Cards | `GlassCard` — material fill + specular stroke + soft shadow |
| Primary CTA | Gradient capsule (orange → deep) |
| Progress HUD | Ultra-thin glass pill, top-center, specular edge |
| Settings sheet | Material sheet |

Implementation: `app/Peel/GlassTheme.swift`, `ContentView.swift`, `ProgressPanelController.swift`, `PeelApp` `GlassWindowChrome`.
