# Licensing, provenance, and third-party notices

Original My City code, documentation, and original art assets are covered by the root [MIT License](LICENSE), to the extent the contributors hold rights in them. Third-party material retains its original license; this document identifies those exceptions and the provenance of bundled art.

## Bundled fonts

| File | Attribution | Retained license |
| --- | --- | --- |
| [`game/assets/fonts/PixelOperator.ttf`](game/assets/fonts/PixelOperator.ttf) | Jayvee Enaguas (HarvettFox96), version 2018.10.04-1 | [CC0 1.0 Universal](game/assets/fonts/PixelOperator-LICENSE.txt) |
| [`game/assets/fonts/PixelifySans.ttf`](game/assets/fonts/PixelifySans.ttf) | The Pixelify Sans Project Authors; design by Stefie Justprince | [SIL Open Font License 1.1](game/assets/fonts/OFL.txt) |

Each TTF's embedded license agrees with its retained license file. Pixel Operator came from [ericoporto's archive](https://github.com/ericoporto/pixel-utf8-fonts/tree/main/pixeloperator); the [author's publication](https://www.dafont.com/pixel-operator.font) confirms CC0 1.0. Pixelify Sans retains the copyright notice from its [upstream project](https://github.com/eifetx/Pixelify-Sans/blob/main/OFL.txt).

Redistributions of Pixelify Sans must retain its copyright notice and full OFL text. My City's MIT license does not replace the font's license. See [Typography](docs/tipografia.md) for how these families are used.

## Art generated for My City

Production records describe PNG sprites generated for this project, followed by cropping, alpha cleanup, scaling, and palette processing using local scripts. Original project art is included in the MIT grant to the extent rights are held by the contributors. Provenance records do not guarantee exclusivity, copyright eligibility, or clearance of third-party rights.

| Collection | Provenance |
| --- | --- |
| Initial characters, accessories, buildings, terrain, furniture, and UI | [`output/imagegen/provenance.json`](output/imagegen/provenance.json), including sources, prompts, and hashes |
| Revised environment and palette variants | [`game/assets/sprites/art-v2/provenance.json`](game/assets/sprites/art-v2/provenance.json) and [accepted package](output/imagegen/art-v2/accepted/35eb357cbca8b91c/provenance.json) |
| HUD icons | [`output/imagegen/hud-icons-provenance.json`](output/imagegen/hud-icons-provenance.json) |
| Directional bicycle sprites | [`output/imagegen/bicycle-directions-provenance.json`](output/imagegen/bicycle-directions-provenance.json) |
| Environmental growth | [`output/imagegen/environment-growth/generation.json`](output/imagegen/environment-growth/generation.json) |

Production records name the requested model `gpt-image-2.5-sunburst-2026-09-08`. Records without a provider response confirming the model explicitly say so; pixels and a model-catalog query alone do not prove which model generated an image. See [Modular art](docs/arte-modular.md) and [Pixel-art production](docs/pixel-art-production.md).

Some records describe failed attempts and others completed generations. Personal `official_cli` paths were replaced with `<IMAGEGEN_SKILL_DIR>/scripts/image_gen.py`. Each modified record contains `privacy_redaction` and a hash of the original document bytes. Historical document hashes identify the pre-redaction record; original image, prompt, and atlas hashes remain unchanged. These hashes are provenance identifiers, not Git commit links.

The art-v2 building, interior, and outdoor generation records also refer to `artifacts/art-direction/before/street-day.png`, a local reference capture that is not tracked. Accepted PNG sources are included, but not every historical input needed to repeat those generation requests is in the repository.

## External tools and services

Godot, Node.js, Bun, Python, and the image-generation CLI are installed separately; their executables are not included here. Art preparation uses Sharp or Pillow as appropriate. Backend dependencies are declared in [`backend/package.json`](backend/package.json) and pinned in [`backend/bun.lock`](backend/bun.lock); installed packages are not tracked.

This inventory does not replace each tool or package's license notices. When distributing an executable, container, or archive containing dependencies, review and retain the notices for the material actually bundled. Cloudflare, Jev, and OpenAI are external integrations governed by their own service terms. This repository's license does not provide credentials, subscriptions, service access, or rights to those providers' trademarks.
