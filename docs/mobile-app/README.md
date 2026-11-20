# Crispy Crust mobile documentation

Read these together:

1. [Original complete build plan](CRISPY_CRUST_BUILD_PLAN.md) — intended full product, architecture, UX, brand, research and acceptance contracts.
2. [Implementation handover and remaining build plan](CRISPY_CRUST_MOBILE_IMPLEMENTATION_HANDOVER.md) — actual implementation, verification, live backend, local setup, exact limitations and continuation work orders.
3. [Owner setup](../../mobile/OWNER_SETUP.md) — required Auth, store, provider, legal and operational configuration.
4. [Current implementation ledger](../../mobile/IMPLEMENTATION_STATUS.md) — F01–F36 source and acceptance coverage.

The implementation is on `feat/flutter-mobile-app`, [draft PR #3](https://github.com/hristianmarkov/crispy-crust/pull/3), not main. Clone the entire repository and check out that branch for local continuation. Historical ZIPs contain planning exports, not the current app source.

`brand-assets/` contains logos, icons, screen references, semantic tokens and font licenses. `SOURCE_PRODUCT_VISION.md` preserves the original vision. `requirements-traceability.csv` is the original feature-ledger template.

The app has substantial implemented source and passing checks, but the full product and release acceptance remain unfinished. See the handover before making infrastructure changes or claiming launch readiness.
