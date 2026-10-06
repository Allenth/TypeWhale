# Concept selection

## Variants explored

- **A — Guided setup.** A connection-first vertical wizard with numbered steps. Strong for first use, but it hides daily status/mappings after setup and makes failure diagnosis feel like restarting onboarding.
- **B — Operational dashboard.** A lead status card followed by device, voice-path, mapping, permission, and help cards. It supports both first use and daily operation on one continuous page.
- **C — Remote map.** A large abstract remote silhouette with callouts around it. It makes mappings memorable but consumes scarce inspector width, risks hardware-brand mimicry, and pushes connection diagnostics below the fold.

## Selected direction

Variant B is approved for implementation. The owner explicitly requested full autonomous development and a complete in-app page after accepting the self-developed architecture. The selection is therefore recorded as an autonomous design decision within that approved scope.

Reasons:

1. It keeps connection truth and the voice pipeline above the fold.
2. It remains useful after first-time setup.
3. It maps directly to TypeWhale's existing inspector groups and scroll container.
4. It avoids external imagery and can support both dark and light TypeWhale themes.

No elements from the rejected variants are required for production v1. Pairing instructions from A are embedded in the device/help cards; C's button-map idea is represented as compact rows instead of an illustration.
