# Yomitan Japanese deinflection data

Tsubame vendors a pinned snapshot of Yomitan's Japanese language transforms and
their tests as the source for its generated deinflection rule resource.

- Upstream: https://github.com/yomidevs/yomitan
- Commit: `77e200428902abf4fa48284df92da7af3dcb4162`
- License: GPL-3.0-or-later; see `LICENSE.txt`
- Runtime resource: `Sources/TsubameCore/Resources/JapaneseDeinflectionRules.json`
- Test fixtures: `Tests/TsubameCoreTests/Resources/YomitanJapaneseDeinflectionFixtures.json`
- Exporter: `Tools/YomitanDeinflectionExporter/export.mjs`

Vendored files and SHA-256 digests:

- `ext/js/language/ja/japanese-transforms.js`:
  `9e928202a2f8f8ed1a17961b3cd93b56cddaf9cdda98b8625dc689f8acdaf2a1`
- `ext/js/language/language-transforms.js`:
  `e454f0a7333170aa1e96e42e546a316aee9c31b8b1d8056d45c034e1470c8a14`
- `ext/js/language/language-transformer.js`:
  `f45db85ae6c5628b65ef0c45d48a47f6091f43109d723f81826dc4a1ce3ae198`
- `test/language/japanese-transforms.test.js`:
  `30dc282e0e3b3fb33c09a995d529b575d6aa84aebc9bf30b566a0c0dfd5e8454`
- `LICENSE.txt`:
  `8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903`

The exporter replaces Yomitan's two rule-construction helpers with declarative
equivalents, evaluates the pinned Japanese descriptor, and writes ordered JSON.
It fails when the pinned files change or a new rule representation appears. No
JavaScript is executed by TsubameCore at build time or runtime.
