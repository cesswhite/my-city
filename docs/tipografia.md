# Interface typography

## Updated compact profile

The profile retains Pixel Operator at 16 px to avoid distorting its strokes. Tabs and actions now reuse HUD atlas icons with flat controls, hover help, accessible names, and visible focus. The active tab adds a marker as well as color. Story actions occupy one 36 px row, freeing space for content.

Reading groups are separated by 12 px, memories by 16 px, and lines retain 4 px of extra spacing. Headings are shortened to the Spanish labels “Ahora” (Now) and “Su historia” (Their story); the activity no longer repeats “Ahora:”. Metrics retain font size, align numbers, and increase contrast. The Appearance portrait sits below navigation, separated from the name field.

Review captures are in `artifacts/resident-panel/after/` and can be repeated with `res://tests/resident_panel_capture.gd -- --ui-test --include-scroll --phase after`. The fixture covers four pages, long text, and accents at 768 × 432 and 960 × 540, without loading saves or calling providers. The following tables preserve the history of the first typography improvement; the profile geometry described above supersedes earlier values.

Reading text uses regular Pixel Operator at **16 pixels**, its design size. Pixelify Sans is reserved for headings of **18 pixels or larger**. Text retains pixel edges, without antialiasing, subpixel positioning, or added tracking. The window continues to use integer scaling over 768 × 432.

## Reading and hierarchy

| Before | After |
| --- | --- |
| Pixelify Sans was also used at 10, 11, 12, and 14 pixels for metadata, paragraphs, and controls. | Pixel Operator at 16 pixels for those uses. The theme and helpers in `game/scripts/main.gd` set the reading font. |
| Headings and body text shared the same decorative family. | Large headings retain Pixelify Sans; frequently read text uses the reading family. |
| Line spacing depended on each panel's helper. | Paragraphs use `line_spacing = 4`, including chat and panels in `resident_ui.gd` and `learning_ui.gd`. |
| Controls were sized for the previous font's metrics. | Sizes, margins, and scrolling areas are reviewed with the 16-pixel font. The test measures text and padding, not just the button rectangle. |

## HUD spacing adjustments

| Before | After |
| --- | --- |
| The Story, Memory, Appearance, and Talk tabs used reduced text to fit. | They retain 16 pixels and use dedicated styles with 3-pixel side margins: the Spanish label “Historia” measures 51 pixels and has 58 available. Change in `main.gd`, tab construction. |
| The input field inherited margins from the graphic asset. | The `main.gd` theme sets 8 horizontal and 4 vertical pixels so text does not touch the edge. |
| The notice scroll measured `(24, 372, 444, 38)`. | It changes to `(24, 374, 444, 42)` for reading text and its lines. Change in `main.gd`, message panel. |
| Small clock, mode, and bottom-guide text had heights designed for 10–12 pixels. | The clock is 18 pixels high and the mode 16, both with 16-pixel text; the bottom guide starts at `y=328` and is 20 high. |
| History used a 16-pixel-high button at `y=352`. | The button is 20 pixels high at `y=350`, matching the new font. |
| Scrollbar styles had zero horizontal margins and could end up with zero visible width. | `main.gd`, `sprite_box()`: track, grabber, and active state have 3 pixels per side, for a visible bar of at least 6. The test requires this width when content extends outside the view. |

## Panels and contrast

| Before | After |
| --- | --- |
| Secondary metadata used `#68735e` and small uppercase headings. | `main.gd`, `resident_ui.gd`, and `learning_ui.gd` use `#535f50` for secondary text; panels use normal mixed case. |
| Inspector columns separated groups by 12 pixels and memories by 16. | `resident_ui.gd`, `_column()` and `build_memories()`: 8 and 12 pixels respectively, with four pixels between lines to maintain reading rhythm. |
| The three Story actions were 26, 26, and 22 pixels high. | `resident_ui.gd`, `build_story()`: 28 pixels high at `y=270/304/338`. |
| Chat status and connection used labels 18 and 12 pixels high. | `resident_ui.gd`, `build_chat()`: 24 and 16 pixels; “Tu turno” (Your turn) avoids a redundant phrase next to the Finish action. |
| Chat text started at `y=112`, suggestions at `y=244` with height 24, and the editor at `y=276` with height 50. | Text starts at `y=116` with height 126; suggestions at `y=248` with height 28; the editor at `y=284` with height 48. The inspector is not enlarged. |
| Suggestions could depend on smaller text to fit. | `_fit_suggestion()` measures width at 16 pixels and uses a short label when needed. It preserves the sent message and shows it fully in the tooltip. |
| The chat footer showed two small shortcut lines next to Send. | The footer at `y=338` is 24 pixels high and shows “Enter: enviar” (Enter: send); field and button tooltips also explain Shift+Enter. |
| Quest cards relied on button text clipping. | `learning_ui.gd`, `quest_cards()`: name and status use multiple word-wrapped lines without clipping content. |
| Journal result text used a shorter region for the old font. | `learning_ui.gd`, `frame()`: scroll at `(16, 312, 684, 42)` for the 16-pixel result. |
| The character name inherited general button margins. | `resident_ui.gd`, `build_appearance()`: input style with 8 horizontal and 4 vertical pixels. |
| Appearance rows had a 34-pixel minimum and two pixels between label and value. | `resident_ui.gd`, `build_appearance()`: minimum 40 and spacing four. |
| Backpack scrolling was 38 pixels high. | `learning_ui.gd`, `frame()`: 42 pixels for inventory at reading size. |
| Headings created by `flow_text()` always inherited the panel font. | `learning_ui.gd`, `flow_text()`: uses `host.label_at()` to select Pixelify for headings of 18 pixels or larger. |
| Some labels declared a tooltip but ignored the mouse. | Labels with tooltips use `MOUSE_FILTER_PASS` so the complete text can be consulted. |

## Continuity and visual checks

| Before | After |
| --- | --- |
| Captures for other features did not provide a typography comparison with identical texts and pages. | `game/tests/typography_capture.gd` produces Story, Chat, Help, Journal, and Appearance with fixed data, before and after, at 768 × 432. |
| The layout suite mainly checked control bounds and overlaps. | `game/tests/typography_smoke.gd` adds Spanish glyphs, measured word spacing, line heights, usable button text, and font/size policy. |
| Draft preservation was checked in general interaction tests. | The new test exactly preserves a draft with accents and a line break, its cursor, and focus after simulated streaming and panel rebuilding. |

The tables describe principles adapted to Godot from the `ui-improvement` and `make-interfaces-feel-better` skills. Font smoothing typical of web interfaces does not apply here: the product requires pixel art text.

## Font and license

Pixel Operator is by **Jayvee Enaguas (HarvettFox96)**. Its [author-published page](https://www.dafont.com/pixel-operator.font) identifies the 16-pixel font and **CC0 1.0** license. The file used comes from [ericoporto's font archive](https://github.com/ericoporto/pixel-utf8-fonts/tree/main/pixeloperator); its [provenance README](https://raw.githubusercontent.com/ericoporto/pixel-utf8-fonts/main/pixeloperator/README.md) points to the same author and page.

`game/assets/fonts/PixelOperator.ttf` and `PixelOperator-LICENSE.txt` are retained. Pixelify Sans retains its SIL Open Font License in `game/assets/fonts/OFL.txt`. Spanish accent availability is verified in the loaded file; coverage of all alphabets is not assumed. These third-party font licenses remain separate from the MIT license for the project's original code, documentation, and art.

## Repeat the check

From the project root:

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path game --script res://tests/typography_smoke.gd -- --ui-test
/Applications/Godot.app/Contents/MacOS/Godot --path game --script res://tests/typography_capture.gd -- --ui-test --phase after
```

The fixture requires `--ui-test`: it creates the real scene with initial data, keeps the clock paused, disables providers, and does not load or save a game. Test streaming is a simulated local signal. Captures are in `artifacts/typography/before/` and `artifacts/typography/after/`.

Tests check `¿¡áéíóúüñÁÉÍÓÚÜÑ`, word spaces of 2–8 pixels in reading text, at least 2 pixels between lines, buttons without ellipses forced by insufficient space, and labels without clipped lines. They also check overlaps after fonts and containers resolve, and scrollbars visibly at least 6 pixels wide when there is overflow. Metrics are printed by family and size.

A passing geometric test alone does not demonstrate readability. Visual comparison must review complete words, accents, punctuation, hierarchy, and sustained reading, as well as compare captures at the same size. Long text in a scroll area may extend outside its visible window; this differs from text truncated inside its own control.

## Measured result

`typography_smoke` passed **37/37 checks** on September 23, 2026, after scrollbar and name-field adjustments. Pixel Operator text at 16 pixels measures **16 pixels of typographic line height and 4 of word spacing**; paragraphs add four pixels between lines. Pixelify headings at 18, 20, and 22 have metric heights of 23, 25, and 28 respectively. The log is in `artifacts/typography/typography-smoke.log`.

The five `before/` PNGs were captured before changing the font configuration, using the same fixture as `after/`. Captures do not depend on the save or provider-generated responses. Automated results cover eight views, including Journal and Shop, plus chat with active typing.

Subsequent integrated validation passed layout **47/47**, chat **60/60**, interaction **21/21**, and learning **31/31**. Visual review of the five final PNGs and a check of the open game confirmed clear reading and scrolling with a visible bar. The clock remains 18 pixels high and the mode label 16; both use the 16-pixel reading font.
