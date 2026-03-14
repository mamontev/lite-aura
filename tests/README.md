## AuraLite Test Suite

Run the suite with:

```powershell
lua tests/run.lua
```

The harness is pure Lua and uses mock WoW APIs so it can run outside the client.

Current focus:

- stable `instanceUID` across save/update/rebuild
- saved position persistence for standalone auras
- group membership and ordering behavior
- synthetic proc rule behaviors like stack caps and duration extension

The suite is intentionally biased toward deterministic behavior and invariant checks.
That matches common testing guidance for event-driven systems:

- test behavior and invariants, not implementation details
- keep tests deterministic and isolated
- use focused unit tests plus a few broader integration-style scenarios
- add coverage tooling later once the base suite is stable

References:

- [GoogleTest Primer](https://google.github.io/googletest/primer.html)
- [GoogleTest FAQ](https://google.github.io/googletest/faq.html)
- [busted documentation](https://lunarmodules.github.io/busted/)
- [LuaCov](https://lunarmodules.github.io/luacov/)
