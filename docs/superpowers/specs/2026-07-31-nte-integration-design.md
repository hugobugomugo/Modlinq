# NTE Integration Design — Merge NTEMM into ZZZ/WUWA Mod Manager

Date: 2026-07-31
Status: approved by Hugo (sections 1-3)

## Goal

One Flutter app manages mods for all three games: Zenless Zone Zero, Wuthering Waves, and Neverness to Everness. Standalone NTEMM (Tauri 2 / React 19 / Rust) is sunset after the merged app reaches feature parity; its user data is imported automatically.

## Scope

Ported from NTEMM:
- `.pak` / `.asi` mod import, enable/disable, delete
- Custom categories with drag & drop ordering
- Automatic game detection
- Built-in `.asi` loader installation
- Anticensor feature (port of `src-tauri/src/mods/anticensor.rs`)
- One-shot importer for existing NTEMM library/config

Explicitly out of scope:
- GameBanana browser for NTE
- NTEMM auto-updater infrastructure (merged app keeps its own release path)
- Any behavior change to existing ZZZ/WUWA management

## Section 1 — Architecture

### Game model

`GameType` (`lib/utils/state_providers.dart`) gains a third value: `enum GameType { zzz, wutheringWaves, nte }`.

### Backend abstraction

New interface `GameModBackend` with two implementations:

- **`MigotoBackend`** — the existing symlink-based logic currently in `ModManagerService`, extracted behind the interface. Serves `zzz` and `wutheringWaves`. Zero behavior change; this is a mechanical refactor.
- **`PakBackend`** — new, serves `nte`. Port of NTEMM's Rust logic (`mods/manage.rs`, `mods/import.rs`, game detection, loader install):
  - App-managed **library folder** holds imported mods (source of truth).
  - Enable = copy `.pak` into the game's `~mods` directory, `.asi` into the loader directory. Exact target paths are taken from NTEMM's `manage.rs` during implementation, not re-invented.
  - Disable = remove the copies from the game directories; library copy remains.
  - Delete = remove from library (and from game dirs if enabled).

Interface sketch (final shape may adjust during implementation):

```dart
abstract class GameModBackend {
  Future<List<ModEntry>> listMods();
  Future<void> importMod(String archiveOrFilePath);
  Future<ApplyResult> enableMod(ModEntry mod);
  Future<ApplyResult> disableMod(ModEntry mod);
  Future<void> deleteMod(ModEntry mod);
}
```

### Apply model: instant with locked-file fallback

Per Hugo's preference, apply is **instant**: file operations execute immediately on toggle. If an operation fails because the file is locked (NTE running on Windows), the operation is appended to a **persisted retry queue** (stored via existing config mechanism). UI shows a "pending — game running" banner for queued items. The queue auto-flushes on app start and on manual refresh. The NTEMM-style batch "pending changes" workflow is NOT ported as the primary model; the queue exists only as the failure fallback.

### Game detection

Ported from NTEMM and extended for Linux:
- **Windows**: registry keys / known install paths as implemented in NTEMM's `game` module.
- **Linux/Proton**: parse Steam `libraryfolders.vdf`, locate the NTE app dir and its Proton prefix; loader install and `~mods` paths resolved inside the prefix.
- Manual path selection always available as fallback (existing pattern in the app).

### Loader installer + anticensor

- Loader install ported from NTEMM: detect presence, install `.asi` loader into the game directory. Exposed as an action in NTE settings.
- Anticensor ported from `anticensor.rs` as an NTE-only settings toggle.

### NTEMM importer

One-shot migration, offered on first switch to NTE if NTEMM data is found:
- Reads NTEMM's config/store (location and format verified from NTEMM source during implementation — `src-tauri/src/app`).
- Copies mod library contents into the new library folder; recreates categories and enabled/disabled state.
- Non-destructive: NTEMM's own data is left untouched.

## Section 2 — UI + Config

- Game switcher gains an NTE entry (same mechanism that switches ZZZ/WUWA today, `mods_screen.dart`).
- NTE view shows a **category list** (NTEMM's organizational model) instead of the character grid. Character grid/tagging code paths are simply not used for `nte`; ZZZ/WUWA screens are untouched.
- `config_service` gains NTE fields: game path, library path, retry queue, anticensor flag.
- New l10n strings added to both `assets/l10n/en.json` and `assets/l10n/uk.json`.
- Character/asset infrastructure (`assets/characters/`, auto-tag alias maps) is not extended to NTE — NTE mods are not character-scoped.

## Section 3 — Testing

- Unit tests for `PakBackend`: import/enable/disable/delete against temp directories; locked-file path simulated → verifies op lands in queue and flushes.
- Unit test for importer against a fixture NTEMM config + library tree.
- Regression guard: `MigotoBackend` extraction covered by existing behavior — `flutter analyze` clean and existing tests pass before/after the refactor commit.
- Manual smoke test on Windows (real NTE install) before NTEMM is archived.

## Migration / Sunset plan

1. Merged app ships NTE support.
2. Hugo validates against his real NTEMM library (importer run).
3. NTEMM repo archived; vault note `02 Projects/NTE Mod Manager.md` moved to archive per vault rules (on instruction).
