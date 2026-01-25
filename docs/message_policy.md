# Message Policy: HUD vs Popup

## Purpose
Keep player onboarding simple and avoid popup fatigue by using the HUD for routine updates and reserving modal popups for high‑impact moments.

## Core rule
**Default to the HUD.** Use a popup only if the message is critical, blocks player control, or requires a decision.

## Popup criteria (use if **any** apply)
1. **Onboarding / first‑time learning**  
   Introduces a new system or mechanic the player must understand to proceed.
2. **Decision required**  
   The player must choose between options or confirm an action.
3. **Critical consequence**  
   Major rewards, penalties, or story changes that should pause attention.
4. **Gameplay interruption**  
   You intend to pause the game to explain or transition.

## HUD criteria (use by default)
- Status updates (ammo, health, cash, heat, objectives).
- Ongoing instructions (“Drive to X,” “Stay in sight,” etc.).
- Non‑critical tips and reminders.
- Minor event confirmations (unless they dramatically change the game state).

## Throttling & pacing
- **Never stack popups back‑to‑back** unless the player explicitly requests the next step.
- **Keep popups short** (title + 1–3 sentences). If it’s longer, split into steps.
- **One‑time onboarding** should be tracked so it doesn’t repeat.
- **Event‑end summary popups** are allowed when they serve a secondary purpose: *preloading the next event while the game is paused*.

## Consistency checklist
- Is this message essential *right now*?  
- Does it require a decision or pause?  
- Would it be understood just as well on the HUD?  
- Will this pause window be used to safely preload the next event?

If the answer is “yes” to decision/pause and “no” to HUD sufficiency, use a popup. Otherwise, keep it on the HUD.

## Implementation proposal (code plan)
This is a high‑level plan for wiring the popup + preload system together while keeping **one** UI app for player onboarding.

### 1) Single messages/tasks app with two modes
- Keep one UI app registered in `types: ["messagesTasks"]`.
- Inside that app, render:
  - **HUD mode** during normal gameplay.
  - **Popup mode** when a message is active (centered panel).

### 2) PopupMessagesManager (GE Lua extension)
Create a manager module responsible for:
- Registering message definitions (id, title, body, priority, once, etc.).
- Queueing and resolving which message to show next.
- Tracking “shown once” flags per save/career.
- Notifying the UI app to enter/exit popup mode.
- Owning the pause/unpause flow.

### 3) Preload hook during popup
When a popup is shown:
- Pause the game.
- Trigger a **preload job** for the next event (vehicles, audio, assets).
- Resume only after the user dismisses the popup (or after preload completes).

### 4) Event lifecycle integration
- Each event (robbery, shooting, etc.) should report:
  - Outcome summary (success/fail, rewards, ammo).
  - Next event identifier.
- The manager builds a **post‑event popup** from that data and queues it.

### 5) Minimal player setup
- Player only enables **one** app in UI Apps.
- All HUD + popup behavior is handled within that single app.

### 6) Suggested message categories
- **Onboarding:** first‑time learning popups.
- **Critical:** major consequences or warnings.
- **Decision:** choices with consequences.
- **Event summary:** post‑event outcome + rewards + preload window.
