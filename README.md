# AuraLite

Addon WoW Retail per tracciare aura selezionate con approccio "WA-lite": scegli aura, poi personalizzi i dettagli.

## Refactor Eseguito

- UI ricostruita in stile editor:
  - colonna sinistra: elenco aura con filtro/selezione
  - colonna destra: editor completo dell'aura selezionata
  - barra quick actions globale (lock, edit mode, compact, source, canale audio, threshold)
- Moduli condivisi introdotti:
  - `AuraLite/SettingsData.lua`: stato e CRUD watchlist, validazioni e mapping dati UI
  - `AuraLite/UIComponents.lua`: factory riusabile per componenti UI (section, button, checkbox, input, dropdown)
  - `AuraLite/SettingsUI.lua`: orchestrazione view modulare (create/edit)
- Riutilizzo logica comune:
  - `ConfigUI` ora usa `SettingsData:EnsureGroup()` quando disponibile.
- Debug mode:
  - nuovo modulo `AuraLite/DebugManager.lua`
  - comando `/al debug` (`on|off|verbose`) per stampare in chat le operazioni interne.
- Autocomplete spell:
  - campo SpellID/Name in UI con suggerimenti dinamici (nome + ID, TAB per selezione rapida)
  - fallback risoluzione nome tramite catalogo locale.
- Nome aura opzionale:
  - campo `Nome Aura (opzionale)` nell'editor
  - usato per identificazione in lista e tooltip in-game.
- Custom text + positioning:
  - campo `Custom text (optional)` per aura con token dinamici
  - positioning per-aura di timer e custom text (`Anchor` + `Offset X/Y`).
- CD visual mode:
  - per aura puoi scegliere `Icon` o `Bar` per il countdown.
- Primary resource condition:
  - per aura puoi abilitare condizione su risorsa primaria player con range `% Min/Max`.
- Localizzazione UI:
  - pannello `Localization` in quick actions
  - lingua di default `English (Default)` con supporto `Italiano`.
- UI moderna + texture custom:
  - nuovo modulo condiviso `AuraLite/UISkin.lua`
  - tema `Modern` (default) e `Classic` dal pannello `Localization / UI`
  - campo `Custom UI texture (optional)` per personalizzare lo sfondo dei pannelli.
- Editor a tab (stile WA-lite):
  - tab `Aura`, `Trigger`, `Display`, `Actions` nel pannello dettagli aura.
  - nel tab `Trigger` il builder regole usa sotto-tab `Trigger | Conditions | Actions`.
- UX/UI revamp modulare:
  - workspace mode `Auras | Editor | Split` con componente segmentato custom
  - `Guided UI` per utenti meno esperti (nasconde campi avanzati)
  - hint contestuali in alto e layout adattivo dei pannelli
  - lista aura con larghezza dinamica per migliorare leggibilita
  - pannello `Rules` in UI per creare/modificare/rimuovere regole senza slash command
  - quick presets nel Rule Builder (`Show Aura`, `Show + Talent`, `Consume Aura`) per setup rapido

## Audio

Sono stati aggiunti preset base extra in `SoundManager` e 3 file audio locali:

- `AuraLite/Media/Sounds/soft_ping.wav`
- `AuraLite/Media/Sounds/bright_chime.wav`
- `AuraLite/Media/Sounds/urgent_alarm.wav`

I preset appaiono direttamente nei dropdown audio della UI.

### Formati audio WoW (PlaySoundFile)

In generale WoW gestisce bene file addon in `ogg/mp3` e in molti casi anche `wav`.
Per file custom per-aura usa il formato token:

`file:Interface\\AddOns\\AuraLite\\Media\\Sounds\\nomefile.wav`

## Struttura File Principali

- `AuraLite/Core.lua`: bootstrap addon e slash command.
- `AuraLite/ProfileManager.lua`: profili (manual/perSpec), export/import.
- `AuraLite/AuraWatchlistRegistry.lua`: normalizzazione e indice watchlist.
- `AuraLite/EventRouter.lua`: eventi WoW -> rebuild dati -> render.
- `AuraLite/TrackerGroupManager.lua`: rendering icone/timer/glow e suoni runtime.
- `AuraLite/SettingsUI.lua`: pannello settings modulare.
- `AuraLite/UISkin.lua`: skin condivisa UI (tema + texture custom).
- `docs/UX_UI_STUDY.md`: studio UX/UI, flussi e principi di design adottati.
- `docs/AuraLite_Audit_and_Roadmap.md`: audit tecnico completo + roadmap implementativa API-safe.
- `AuraLite/SpellCatalog.lua`: ricerca/autocomplete spell.
- `AuraLite/SpellCatalogData.lua`: dataset locale generato da Wowhead.
- `AuraLite/DebugManager.lua`: logging debug.

## Uso Rapido

- `/al config` oppure `/al ui`: apre il pannello editor.
- `/al lock` / `/al unlock`: blocca/sblocca drag gruppi.
- `/al edit`: abilita/disabilita placeholder mode.
- `/al sound`: toggle audio globale.
- `/al debug`: toggle debug chat.
- `/al debug on|off|verbose`: controllo esplicito debug.

## Test

Per eseguire la batteria di test Lua locale:

`powershell -ExecutionPolicy Bypass -File .\run-tests.ps1`

Per eseguire il gate di beta readiness con report:

`powershell -ExecutionPolicy Bypass -File .\run-beta-gate.ps1`

La suite attuale copre soprattutto:

- identita` stabile delle aura (`instanceUID`) su create/update/rebuild
- persistenza posizione/saved state su update
- gruppi: create, move, delete container, ordering
- proc rules sintetiche: stack, decrement consume, extend-to-cap, expiry
- import/export di aura singola e gruppi con riallocazione sicura degli ID locali
- stress/stateful tests su sequenze ripetute di update/rebuild/group/ungroup

Il gate beta aggiunge anche:

- syntax check di tutti i file Lua dell'addon
- report `GO / NO-GO` in `tests/out/beta-readiness-report.txt`
- controllo base di hygiene sui log diagnostici temporanei

L'idea e` usare test stateful e boundary-oriented sui punti piu` fragili del runtime, e poi completare con smoke test in-game per le API specifiche del client WoW.

## Packaging e Release

Per creare uno zip beta locale:

`powershell -ExecutionPolicy Bypass -File .\package.ps1 -Channel beta -Label beta1`

Lo zip viene generato in `dist/` e contiene `AuraLite/` come root, pronto per distribuzione manuale.

Per la checklist di rilascio:

- `docs/BETA_RELEASE_CHECKLIST.md`

Per il testo base della release:

- `docs/RELEASE_TEXT_BETA.md`

Per preparare auto-packaging tipo CurseForge/BigWigs packager:

- `.pkgmeta`

### Personalizzare texture UI

1. Importa una texture in `AuraLite/Media/Custom`:

`powershell -NoProfile -ExecutionPolicy Bypass -File .\import-texture.ps1 -SourcePath C:\path\myTexture.png`

2. Apri `/al ui` -> `Localization / UI`.
3. In `Custom UI texture (optional)` inserisci:
   - nome corto (es. `myTexture`) oppure
   - path completo WoW (es. `Interface\\AddOns\\AuraLite\\Media\\Custom\\myTexture`).
4. Premi `Apply`.

### Token Custom Text

Nel campo custom text puoi usare:

- `{name}` nome aura personalizzato (fallback nome spell)
- `{spell}` nome spell
- `{stacks}` stack correnti
- `{remaining}` tempo rimanente
- `{duration}` durata base
- `{source}` label source
- `{unit}` unit monitorata

## Aggiornare Catalogo Wowhead

Per rigenerare il catalogo spell usato dall'autocomplete:

`powershell -NoProfile -ExecutionPolicy Bypass -File .\sync-wowhead-spells.ps1 -MaxEntries 6000`

## Restrizioni API in Combat (Retail 12.x)

- Blizzard ha introdotto `Secret Values` / `Restricted Actions`: in certi contesti i cooldown spell possono essere nascosti agli addon.
- Quando `SecretCooldowns` è attivo, AuraLite non prova a leggere cooldown non consentiti (evita errori Lua e falsi positivi nel debug).
- Se esiste uno storico cooldown per quella spell, AuraLite usa un fallback di stima (avvio su cast) finché la restrizione è attiva.
- In questi casi può funzionare il tracking aura (buff/debuff), mentre il tracking cooldown spell può risultare parziale o non disponibile finché la restrizione resta attiva.

## Proc/Consume Rule Engine

- Trigger cast in combat via path sicuro:
  - hook non-protetti (`CastSpellByID`, `CastSpellByName`, `UseAction`, `C_Spell.CastSpell`)
  - conferma tentativi via cooldown/GCD edge polling (close-enough, taint-safe)
- Motore regole in `AuraLite/ProcRuleEngine.lua`:
  - `ifAll` conditions con logica `AND/OR`
  - liste multi-clausola CSV su cast/talent/required-aura
  - `thenActions` / `elseActions`
  - azioni `showAura`, `hideAura`, `decrementAura`
  - regole custom salvate nel profilo: `ns.db.procRules`
- Modalita consigliata: `Rules Only` (default ON) per usare solo il motore regole come source di attivazione aura.
- Comandi rapidi:
  - `/al rule list`
  - `/al rule addif <id> <castSpellID> <talentSpellID> <auraSpellID> <durationSec>`
  - `/al rule addconsume <id> <castSpellID> <auraSpellID>`
  - `/al rule remove <id>`
  - `/al rule clear`
- Esempio Phalanx:
  - `/al rule addif phalanx_show 6343 1278009 1278009 8`
  - `/al rule addconsume phalanx_consume 23922 1278009`

## Note Dev

L'ordine di load nel `.toc` e stato aggiornato per caricare i moduli condivisi prima di `SettingsUI`.
