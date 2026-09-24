# The colony fills the screen

Previously, the map occupied 468 × 244 within a 768 × 432 logical interface: roughly 34% of the area. World layers now cover the entire viewport. With no panel open, the map retains its proportions, stays centered, and extends edge terrain for other aspect ratios.

The three HUD groups occupy less than 10% of the base view. They are translucent dark surfaces with icons, focus, and help. Profile, memory, appearance, and chat open only on request. Opening them changes neither map size nor navigation coordinates. Panel areas block both clicks and object glow behind them.

Automatic neighborhood events remain in history without opening a log over the map. Action confirmations and errors appear for 5.5 seconds and can be dismissed manually. Interaction hints appear when a relevant action exists. Resident labels are drawn at 16 logical pixels, independently of world zoom, and avoid visible panels. Bed rest retains its timed indicator and wake button; exhaustion shows only the mandatory recovery counter.

When opening the profile of someone present, the camera keeps them clear of the panel and controls. If the player is nearby, it includes both; during conversation, the active pair takes priority even while viewing another profile. The shift uses actual sprite bounds, including hats and feet, with margins from the chat, indicators, and dock. It preserves scale and physical coordinates. Object, character, environment, and lighting layers share the same transform, also used to resolve clicks and object glow. The transition lasts 0.24 seconds, can be interrupted, and works while paused. Closing the panel restores the general framing; resizing readjusts immediately.

Opening a profile alone does not stop the neighbor. "Hablar" (talk), "Conversar cerca" (talk nearby), and **E** reserve both participants before the first message is written. The reservation persists between replies and blocks pending home entrances or exits; afterward, the neighbor resumes their current destination. The rest of the neighborhood continues.

Framing validation: `conversation_camera_smoke.gd` **90/90**, `overlay_smoke.gd` **29/29**, and `responsive_smoke.gd` **71/71**, at 768×432, 960×600, and 1280×540. Checks cover map edges, interiors, transitions and target changes, resizing with a draft, every layer, and object clicks. The complete session passed `player_chat_smoke.gd` **128/128**, including initial draft, active schedules, decisions, portals, and release. Controls also passed **47/47**, hover **35/35**, modals **58/58**, core **141/141**, AI autonomy **50/50**, menu **34/34**, and service **73/73**. Tests are isolated, with no provider usage or save modification.

Five rendered captures were reviewed in `artifacts/conversation-camera/`: outdoor views at 768×432 and 960×540, and daytime/nighttime indoor and outdoor views. Examples: outdoor conversation (`artifacts/conversation-camera/street-right-day-960.png`) and indoor conversation (`artifacts/conversation-camera/interior-right-night-960.png`). Session logs are in `artifacts/conversation-hold/`. These historical validation artifacts are local and excluded from Git.

Collapsing a panel preserves draft, cursor, and scroll position without restarting a conversation. A response received while the panel is hidden does not reopen it. The chat's × ends the encounter and clears chat according to its previous contract. Walking returns attention to the world. Esc retains this priority: modal, editor focus, character panel, menu.

The pause menu shows the last game scene with simulation and input suspended. Settings, saving, and new-game backups retain their logic. Menus and panels use brief fades without blur or new images.

Isolated verification: `overlay_smoke` (29), `responsive_smoke` (71), `hud_smoke` (96), and `activity_labels_smoke` (15). Tests exercise actual viewport events, different aspect ratios, typing during streaming, closing, reopening, and click blocking. Captures in `artifacts/fullscreen-overlay/` show the world, profile, chat, appearance, and interior.
