# Codex Rules

## BeamNG API verification rules
- **Always verify BeamNG APIs against the dump** before using them in code.
  - Primary: `docs/beamng-api/raw/api_dump_0.38.txt`
  - Secondary: `docs/beamng-api/raw/api_dump_0.38.json` (for structure)
- If a symbol is not found in the dump, **do not implement it as if it exists**.
  - Instead: add a guard (`pcall`, `nil` checks) and a fallback or no-op.
- When a BeamNG API is used in new code, add a short comment:
  - `-- API dump ref: docs/beamng-api/...`
- Prefer adding new BeamNG interactions via a wrapper function (future-proofing). If not feasible, at least centralize repeated calls.

## Required workflow for new features
1. Identify candidate APIs (initial guess is okay).
2. Verify each candidate in the dump (TXT search or `tools/api_lookup.py`).
3. Use only verified APIs, or add guarded fallbacks for missing symbols.
