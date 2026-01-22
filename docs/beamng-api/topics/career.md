# Career topic

## Purpose
Document Career-mode APIs used by this mod, with emphasis on player attributes (wallet) and payment helpers. These functions are defined in the GE dump under `career_modules_playerAttributes`, `career_modules_payment`, and `career_career`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L1294-L1307】【F:docs/beamng-api/raw/api_dump_0.38.txt†L1324-L1361】【F:docs/beamng-api/raw/api_dump_0.38.txt†L5217-L5222】

## Common tasks
- Read wallet/attributes via `career_modules_playerAttributes.getAttributeValue` or `getAttribute`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L1294-L1301】
- Set multiple attributes in a single call with `career_modules_playerAttributes.setAttributes`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L1296-L1299】
- Apply payments/rewards with `career_modules_payment.canPay`, `pay`, and `reward`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L5217-L5222】
- Detect career activity using `career_career.isActive` when available.【F:docs/beamng-api/raw/api_dump_0.38.txt†L1324-L1347】

## Verified APIs (from dump)
Player attributes:
- `career_modules_playerAttributes.getAttributeValue(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L1294-L1301】
- `career_modules_playerAttributes.getAttribute(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L1294-L1300】
- `career_modules_playerAttributes.getAllAttributes(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L1294-L1307】
- `career_modules_playerAttributes.addAttributes(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L1294-L1297】
- `career_modules_playerAttributes.setAttributes(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L1296-L1299】

Payment helpers:
- `career_modules_payment.canPay(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L5217-L5220】
- `career_modules_payment.pay(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L5217-L5221】
- `career_modules_payment.reward(...)`【F:docs/beamng-api/raw/api_dump_0.38.txt†L5217-L5222】

Career lifecycle:
- `career_career.isActive()` and lifecycle hooks such as `activateCareer`, `deactivateCareer`, `launchMostRecentCareer`.【F:docs/beamng-api/raw/api_dump_0.38.txt†L1324-L1358】

## Notes / gotchas
- The dump lists attribute accessors like `getAttributeValue` but does **not** list `setAttributeValue` or `addAttributeValue` even though they may exist in some builds; keep guarded fallbacks (as the mod already does).【F:docs/beamng-api/raw/api_dump_0.38.txt†L1294-L1301】【F:lua/ge/extensions/CareerMoney.lua†L6-L73】
- Use `career_career.isActive()` where available instead of relying solely on `careerActive` globals, which may be absent in some contexts.【F:docs/beamng-api/raw/api_dump_0.38.txt†L1324-L1347】【F:lua/ge/extensions/CareerMoney.lua†L75-L93】

## Example usage patterns (mod-specific)
- Wallet helper wraps `career_modules_playerAttributes.getAttributeValue` and guards missing setters with fallback logic when career APIs are unavailable.【F:lua/ge/extensions/CareerMoney.lua†L6-L73】
- Robber events use `career_modules_payment.canPay`, `pay`, and `reward` for money transfer operations when in Career mode.【F:lua/ge/extensions/events/RobberEMP.lua†L147-L166】
