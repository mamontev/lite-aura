# AuraLite Beta Release Checklist

## Pre-release

- Bump `## Version:` in `AuraLite/AuraLite.toc`
- Run:
  - `powershell -ExecutionPolicy Bypass -File .\run-tests.ps1`
  - `powershell -ExecutionPolicy Bypass -File .\run-beta-gate.ps1`
- Verify `tests/out/beta-readiness-report.txt` says `BETA READY: YES`
- Smoke test in game:
  - standalone aura keeps position after `Save Aura`
  - grouped aura move together with movers
  - import/export aura works
  - import/export group works
  - stackable buff logic works
  - extend-to-cap timer logic works

## Package

- Local beta zip:
  - `powershell -ExecutionPolicy Bypass -File .\package.ps1 -Channel beta -Label beta1`
- Check output in `dist/`
- Open the zip and verify the root folder is `AuraLite/`

## Publish

- GitHub:
  - create tag matching the addon version
  - attach the zip from `dist/`
  - paste the beta release text from `docs/RELEASE_TEXT_BETA.md`
- CurseForge:
  - upload the same zip or use auto-packaging
  - set release type to `Beta`
  - add project summary and changelog
- WoWInterface:
  - optional mirror of the same beta zip

## Post-release

- Install the published package on a clean addon folder
- Verify the addon boots without local dev files
- Monitor first feedback:
  - import failures
  - mover/position regressions
  - group layout regressions
  - spell-trigger false positives

