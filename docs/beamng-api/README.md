# BeamNG API Dump (v0.38)

## What this is
This folder is the source of truth for BeamNG APIs referenced by this mod. The raw dumps come from the exact BeamNG version we target (0.38).

## Where the files live
- Raw dumps: `docs/beamng-api/raw/`
  - `api_dump_0.38.txt` (primary search target)
  - `api_dump_0.38.json` (secondary, structured reference)
- Indexes: `docs/beamng-api/index/`
- Topic notes: `docs/beamng-api/topics/`
- Curated shortlist: `docs/beamng-api/bolides_api_shortlist.md`

## How to use it
1. Search the TXT dump first for fast discovery (it is the quickest way to confirm symbols exist).
2. Use the JSON dump if you need structure or want to confirm table layouts.
3. Verify every BeamNG API before using it in code. See `docs/CODEX_RULES.md`.

### Quick search tips
- VSCode: `Ctrl+Shift+F` → search `docs/beamng-api/raw/api_dump_0.38.txt`
- Recommended queries:
  - `createSFXSource`
  - `playSFX`
  - `career_modules_`
  - `core_`
  - `ai.`
  - `spawn`
  - `imgui`
  - `vehicle:` / `obj:`

## Rules for new code
Before adding any BeamNG function/table usage, verify the symbol in `api_dump_0.38.txt` (primary) or `api_dump_0.38.json` (secondary). If a symbol is missing, do not assume it exists—guard it or provide a fallback.

## Regenerating indexes
Run the indexer script (from repo root):

```
python tools/api_indexer.py
```

This regenerates:
- `docs/beamng-api/index/index_modules.md`
- `docs/beamng-api/index/index_functions.md`
