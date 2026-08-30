# AGENT.md

Working knowledge for automated agents and contributors working on this repository.

## Standards

This repository follows the [robotsix-standards](https://github.com/damien-robotsix/robotsix-standards). All agents and contributors should read and conform to the applicable standards before making changes.

**Repo tier:** 3 (mobile application)

## Rules

<!-- Accumulate repo-specific conventions, gotchas, and working knowledge below. -->

### Flutter / Dart

- This is a pure Flutter/Dart project. Python-specific, Docker, config, and component standards do **not** apply.
- Lint rules are defined in `analysis_options.yaml` via `package:flutter_lints/flutter.yaml`.
- Run `flutter analyze` for static analysis and `flutter test` for the test suite.
- CI is defined in `.github/workflows/ci.yml` and runs on push/PR to `main`.

### Changelog

- Release notes come from **release-please + conventional commits** only. There is no changelog fragment layer.
- Commit subjects and PR titles must be conventional (`feat:`/`fix:`/`chore:`/`docs:`/`refactor:`/`test:`/`ci:`); release-please generates `CHANGELOG.md`.

### Module registration

- Module paths are registered in `docs/modules.yaml`. New source files must be added there.
