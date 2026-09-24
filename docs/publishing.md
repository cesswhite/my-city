# Publishing and licensing

My City is released under the [MIT License](../LICENSE). It permits reuse, modification, redistribution, and commercial use of original project code, documentation, and original art to the extent contributors hold rights in them. Retain the required copyright and license notice. Bundled fonts and third-party material keep their own licenses; see [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).

Public source does not deploy the Worker or share local credentials. Distributing a game connected to a public hosted service is a separate step and requires the controls described in [SECURITY.md](../SECURITY.md).

## Publication boundaries

1. **Visibility and copies.** Shared code, assets, prompts, and history become accessible. Others can fork the project; making it private later does not retract their copies. Actions logs also become visible. [GitHub visibility documentation](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/managing-repository-settings/setting-repository-visibility).
2. **Private data.** Review files and all published references, including author email, machine paths, attachments, and logs. Git exclusions do not clean old commits. Exposed credentials require rotation even after the file is removed.
3. **License scope.** MIT covers the original project material, not external providers, subscriptions, third-party trademarks, or separately licensed dependencies. It does not require downstream users to publish their modifications. [MIT license reference](https://choosealicense.com/licenses/mit/).
4. **Third-party material.** Preserve font and dependency notices. Generated-art provenance does not establish exclusivity or override third-party rights.

## Preparing a release

- Check that a clean clone imports `game/project.godot` and runs tests without the author's `.env`, private caches, or credentials.
- Keep local startup independent of image generation and paid model calls. Configured models depend on access and availability in each account.
- Keep credential templates empty and fixtures synthetic. Scan for actual configured secret values and credential signatures without printing matches into reports.
- Run automation without secrets on external contributions. A pull request must not trigger deployment or image generation by default.
- Check captures and distribution packages for personal saves, tokens, and sensitive paths.
- Use a protected commit email and audit the complete published history. A history rewrite does not guarantee deletion from third-party clones or hosting-provider caches; verify what the new public repository can actually serve.

## Art reproducibility limits

Runtime sprites are included; playing does not require regenerating them. Records preserve source images, prompts, requested models, and hashes. Some production files describe tools and captures from the original environment that are not part of a clean installation. An image API is not guaranteed to reproduce an identical output. Read [visual production](pixel-art-production.md) before repeating a batch and preserve perspective, scale, and anchor checks.

This guide does not itself authorize another visibility change, history rewrite, deployment, or license change. Those are explicit project-owner decisions.
