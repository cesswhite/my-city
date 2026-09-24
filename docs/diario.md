# Journal

The journal places errands on the left, the backpack below them, and errand details on the right. The balance appears in the header. Reading text retains Pixel Operator at 16 native pixels; headings use Pixelify Sans, and groups are separated by 12 or 16 pixels.

## Next action

The "Qué hacer ahora" (what to do now) card explains the pending step. The primary button is chosen from the actual world state:

| Situation | Primary action |
| --- | --- |
| Errand not started, mentor far away | Go to the mentor |
| Errand not started, mentor nearby | Accept the errand |
| Missing materials | Go to the shop |
| Materials ready, mentor far away | Go to the mentor |
| Materials ready, mentor nearby | Deliver materials |
| Lesson learned, project far away | Go to the project at home |
| Beside the project | Perform the next step |
| Learning completed | Show knowledge, steps, and result; no disabled button |

Mentor proximity includes the room but does not require their workplace. Actions still go through Colony validation; opening the journal does not grant materials, knowledge, or rewards. If a character moves before the click, the rules validate the action again and the journal displays the response.

## Reading and controls

- Cards show a short title, mentor, and status. The full title is in the tooltip and accessible name.
- Materials show available/required quantities. A checkmark accompanies the color once they are complete.
- Completed steps have a checkmark. Pending steps retain their order, and the result appears once practice is complete.
- "Sobre este encargo" (about this errand) expands the story when you want to read it.
- The backpack shows every item with aligned quantities and independent scrolling for long lists.
- Actions stay outside the detail area's scroll region. The primary action receives focus; Tab, arrows, and Enter stay within the modal. Esc closes it.
- The modal is centered and adjusts between 720 × 392 and 840 × 480 according to the window, without rebuilding or losing focus on resize.

The shop shares the journal's presentation: materials, price, reason for availability, and purchase of one unit, using the player's actual balance.

## Verification

`learning_world_smoke.gd` traverses the complete quest using actual buttons, the shop, a mentor who changes location, and practice at home. Its selectors use action metadata rather than depending on button text. `typography_smoke.gd` checks fonts, accents, spacing, overflow, and overlap. `responsive_smoke.gd` also checks shrinking an open modal while retaining focus and its nodes.

`journal_capture.gd -- --ui-test --phase after --include-scroll` captures not-started, materials missing/ready, lesson learned, empty backpack, four completed steps, and long-backpack states. The fixture constructs valid states through local engine actions without touching the actual save or consulting providers. Captures: `artifacts/journal/before/` and `artifacts/journal/after/`.
