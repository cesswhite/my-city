# House interface

Location and exit share a compact card between player status and clock controls. When exploring an interior, the journal and bicycle bar occupies a small corner at the bottom left, leaving the room's center and entrance mat clear. The bicycle indicates that it can only be used outdoors.

## Exploring and reading

- Objects retain their hover glow. The hint shows the object's name and available action.
- Clicking starts the route; you can also press E when nearby. Knowledge is recorded only upon reaching the actual interaction point.
- The object's title and full text appear at the bottom right in a compact dark card. It uses Pixel Operator at 16 pixels for the title and 14 for the body, with spacing between groups and scrolling for long text.
- The card adjusts its height to the content. The camera keeps the player visible in the free area without changing their coordinates or the world's scale.
- Esc, Enter on the close control, or × closes the text. Walking, choosing another action, opening the journal or a profile, and changing rooms also close it. Reading does not pause the clock.
- The cabinet in your home acts as a **wardrobe**. It highlights on hover; clicking walks toward it, and E uses it nearby. This is the only place where you can change name and appearance. Player profiles outside the wardrobe and neighbors' profiles show appearance in read-only mode.
- The player's bed and projects still open their rest and learning actions.
- Leaving walks the player to the door. Presentation does not change visiting rules, trust, or collisions.

Inspection no longer depends on a short notice that clips the text. Observed memories remain available in the character's memory; hovering or opening a house does not reveal them.

## Verification

`home_ui_capture.gd -- --ui-test --phase before|after` captures all six houses at two sizes using an isolated synthetic world. `home_ui_smoke.gd` checks inspection, navigation, reading, keyboard, closing, and exiting. `reading_camera_smoke.gd` checks framing; `world_smoke.gd`, `hover_ui_smoke.gd`, `responsive_smoke.gd`, and `hud_smoke.gd` verify existing interactions and layouts.

Captures: `artifacts/home-ui/before/` and `artifacts/home-ui/after/`. Fixtures neither load nor save the player's game and do not consult external services.

`closet_ui_smoke.gd -- --ui-test` validates wardrobe interaction by click and keyboard, editing at its physical location, compact shortcuts, and AI enabled by default when configured, without making requests. With `--capture`, it saves street, bench, wardrobe, and customization views in `artifacts/closet-ui/`.
