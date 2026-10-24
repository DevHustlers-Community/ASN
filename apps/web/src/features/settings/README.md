# Settings & Preferences Feature (`src/features/settings`)

**Status:** planned — no implementation yet.

Manages user profile configuration, UI theming, and account lifecycles.

## Core Capabilities

1. **Appearance Customization:**
   - Surface mode: OLED Black / Dim Slate / Clean Light.
   - Primary Accent: Emerald / Indigo / Amber / Crimson / Cyan.
   - Corner Radius: Sharp (6px) / Balanced (12px) / Soft (20px).
2. **Privacy & Security:**
   - Message privacy setting aligned with schema: `chat_privacy_settings.allow_non_friend_messages` (boolean).
   - E2EE device key fingerprint verification display (planned).
3. **Account Deletion Workflow:**
   - 30-day legal grace period initiation and cancellation.
   - Status banner with remaining days countdown.
