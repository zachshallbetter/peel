# Peel — unified product contract

**Status:** Product direction, 2026-10-19. Features not marked qualified remain proposed.

## Identity and promise

One application, one icon, one identity: **Peel — Open what's inside.** Do **not** split Peel into Extract/Explore/Protect products. The orange peeled-sticker identity remains canonical; format indicators must remain legible and accessible. Advanced functions are contextual features within Peel, not separate branded apps.

The differentiator is **container-aware file interaction**: supported archives, document packages, installers, optical media, and images can be understood through the same UI without pretending their physical semantics are identical. Finder is the preferred macOS surface wherever public APIs and user consent permit; a native Peel browser remains necessary for unsupported Finder behaviors.

## Everyday workflows

1. **Extract:** associate a supported archive with Peel; double-click or Open With follows the user's configurable extract/browse preference. Stage output, handle collisions safely, report real progress and verification coverage.
2. **Inspect:** press Space on an archive for a Quick Look summary, file tree, size, protection findings, and supported actions. Do not claim an interactive Finder directory from Quick Look alone.
3. **Browse:** open a container tree in Peel or, where available, a read-only PeelFS mount in Finder. Search names, view metadata, select entries, and navigate supported nested containers.
4. **Open inside:** request only needed entry bytes; launch associated applications from a managed, access-controlled materialization. An external application's save does not silently mutate the archive.
5. **Protect:** identify encryption scheme, header exposure, authentication limitations, and actionable migration options; unlock known-password archives without an upgrade.
6. **Recover:** after free feasibility analysis and consent, Pro may run bounded local password-candidate verification or other validated authorized methods. Present measured limitations and non-guarantees.
7. **Repair protection:** after successful unlock, create a new protected output, independently verify a complete round trip, preserve the source, and report losses/limitations.

## Free and Pro boundary

| Capability | Free | Pro |
| --- | :---: | :---: |
| Common extraction and creation; known-password unlock | Yes | Yes |
| Strong encrypted archive creation | Yes | Yes |
| Archive browsing, Quick Look, Finder integration | Yes | Yes |
| Selective extraction, previews, basic verification | Yes | Yes |
| Encryption identification and weakness explanation | Yes | Yes |
| Free recovery feasibility estimate | Yes | Yes |
| Guided forgotten-password recovery and reconstruction | No | Yes |
| Bounded CPU/GPU recovery acceleration (where validated) | No | Yes |
| Narrow, reproducible legacy-cipher research adapters | No | Yes |

Pro entitlement should be checked at the recovery workflow boundary, not inside basic archive decoders. Keep the user informed about compute/time/disk/energy cost. No default cloud upload or secret escrow. A one-time **$29–$49** price is a validation hypothesis; licensing, offline activation, upgrades, and platform parity remain open decisions.

## UX principles and constraints

- Minimal, native, accessible; ordinary extraction must not require a dashboard.
- Format detection is based on signatures and bounded structural validation, not extension alone.
- Honest labels: detected, readable, listable, extractable, verified, conditional, unsupported, qualified.
- Never equate a listed entry with payload verification; never say 'broken' without demonstrated applicability.
- Preserve explicit controls for opening, extracting, copying, ejecting, and cleaning up.
- Respect reduced motion, keyboard navigation, VoiceOver, secure password prompts, and consent boundaries.

## Out of scope until separately designed

Universal EXE/PAK decoding; running installers; arbitrary writable archive mounts; modifying signed packages without warning; generic bypass of modern AES; silently mounting disk images; guaranteed password recovery; unreviewed bespoke cryptography.
