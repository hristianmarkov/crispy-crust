# Crispy Crust identity and screen assets

Created 11 November 2026 for planning/handoff. These assets are proposals, not a claim of trademark clearance or user testing.

- Authoritative logo masters: `mark-olive.svg`, `mark-ivory.svg`, `mark-ink.svg`, `wordmark-horizontal.svg`, `app-icon-master.svg`.
- Authoritative UI proposal: `design-tokens.json` and `screen-blueprints.svg`.
- PNG files preview their matching SVG masters; `brand-concept.png` is image-generated concept art and has no matching vector master.
- `screen-blueprints.png` contains illustrative fixture recipes, labels and times. It must not become a source of validated recipe timing or real user observations.
- `small-size-inspection.png` is an optical check at 16/24/32/48/64px, not a user-recognition study. Recognition as bread rather than a generic C/croissant still needs testing.
- App-icon PNG is opaque 1024×1024. Generate native iOS/Android resources and adaptive masks from the master during implementation; do not bake a rounded mask into store artwork.
- Wordmark and blueprint typography are outlined paths for fidelity. Runtime app text must remain actual semantic text, not SVG text outlines.
- The logo mark is hand-authored SVG from this planning session, not extracted from an existing competitor logo. Formal similarity/trademark review is still outstanding.

Fonts downloaded from the maintained Google Fonts source repository, with their OFL notices preserved:

- DM Sans Variable: https://github.com/google/fonts/tree/main/ofl/dmsans
  SHA-256 `8cd08d97e89c24d0aa92edd2f0f4c8ee6195eee9b7c9f154865a58b02f0c1c0d`
- DM Serif Display Regular: https://github.com/google/fonts/tree/main/ofl/dmserifdisplay
  SHA-256 `8cc3643535edf039aa5d95440a8542735e9197e4f4b8d9303e980fefbf5ab616`

Validation performed: 7 SVGs parsed as XML; 5 PNGs decoded; design-token JSON parsed; WCAG contrast pairs calculated; small-size mark and six-screen board visually inspected. No Flutter app or native accessibility test was performed.
