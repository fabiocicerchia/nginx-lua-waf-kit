# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.1](https://github.com/fabiocicerchia/nginx-lua-waf-kit/compare/v1.3.0...v1.3.1) (2026-09-04)

### Bug Fixes

- **ci:** pin the editorconfig-checker binary version ([#36](https://github.com/fabiocicerchia/nginx-lua-waf-kit/issues/36)) ([834d6fd](https://github.com/fabiocicerchia/nginx-lua-waf-kit/commit/834d6fd7ae0ba627d9d53b45b92327c19e2bbf95))

## [1.3.0](https://github.com/fabiocicerchia/nginx-lua-waf-kit/compare/v1.2.1...v1.3.0) (2026-09-03)

### Features

- a log_only rollout that can actually be counted, and a reproducible bench ([#32](https://github.com/fabiocicerchia/nginx-lua-waf-kit/issues/32)) ([f17213b](https://github.com/fabiocicerchia/nginx-lua-waf-kit/commit/f17213b7408284bcb8d8682a27bc7992bf43939f))

## [1.2.1](https://github.com/fabiocicerchia/nginx-lua-waf-kit/compare/v1.2.0...v1.2.1) (2026-08-29)

### Bug Fixes

- unblock quality and clear the Scorecard pinned-dependencies finding ([#26](https://github.com/fabiocicerchia/nginx-lua-waf-kit/issues/26)) ([4df6f2f](https://github.com/fabiocicerchia/nginx-lua-waf-kit/commit/4df6f2fd85d670c94776b6b1f06f8b050bb615ef))

## [1.2.0](https://github.com/fabiocicerchia/nginx-lua-waf-kit/compare/v1.1.0...v1.2.0) (2026-08-25)

### Features

- **docs:** build the docs site in Actions and drop Read the Docs ([#24](https://github.com/fabiocicerchia/nginx-lua-waf-kit/issues/24)) ([c973aa5](https://github.com/fabiocicerchia/nginx-lua-waf-kit/commit/c973aa5af4c23332b407c1b705f253e148faa3ec))

## [1.1.0](https://github.com/fabiocicerchia/nginx-lua-waf-kit/compare/v1.0.1...v1.1.0) (2026-08-24)

### Features

- **examples:** tag each example config set against its nginx-lua release ([#17](https://github.com/fabiocicerchia/nginx-lua-waf-kit/issues/17)) ([558b267](https://github.com/fabiocicerchia/nginx-lua-waf-kit/commit/558b26752af59fda9ab28d5b64576e3fe00a4de9))

## [1.0.1](https://github.com/fabiocicerchia/nginx-lua-waf-kit/compare/v1.0.0...v1.0.1) (2026-08-13)

### Bug Fixes

- security and code-quality findings ([#14](https://github.com/fabiocicerchia/nginx-lua-waf-kit/issues/14)) ([f9f4d77](https://github.com/fabiocicerchia/nginx-lua-waf-kit/commit/f9f4d77e55062a95f0b8429fe6a2c7f569781626))

## 1.0.0 (2026-08-06)

### Bug Fixes

- **ci:** stop security workflows failing on private repos ([#2](https://github.com/fabiocicerchia/nginx-lua-waf-kit/issues/2)) ([c5f16b5](https://github.com/fabiocicerchia/nginx-lua-waf-kit/commit/c5f16b58d5b81c4f5306bf0d1fd1a8df3fb7c8fc))
- **pre-commit:** stop check-yaml failing on Helm templates and multi-doc manifests ([25be2b1](https://github.com/fabiocicerchia/nginx-lua-waf-kit/commit/25be2b15e6cd6302eb9586bc6ae8eff7a1c4a5c9))
- **ratelimit:** decode shared-dict state correctly ([cbaf05f](https://github.com/fabiocicerchia/nginx-lua-waf-kit/commit/cbaf05fd21df21d791c45bc76697d944b80337ad))
- **security:** skip the SARIF upload on private repos ([9258635](https://github.com/fabiocicerchia/nginx-lua-waf-kit/commit/9258635c11f529bc5991ef13e36abab50c9a53de))

## [Unreleased]

### Added

- CI now runs the Lua test suite; it was never executed anywhere before.
- Test coverage for the enforcement entry points (`ratelimit.limit`,
  `jwt.require_token`, `geo_asn.check`), for mirror scrubbing and shipping, for
  JWKS key selection, and for the HS256 validation success path.

### Changed

### Deprecated

### Removed

### Fixed

- `mkdocs.yml` failed to parse: an unquoted `:` in `site_description` made YAML
  read the value as a nested mapping.

### Security

- **Rate limiting was inoperative.** `ratelimit.decode` split the shared-dict
  state with a pattern that also matches the empty string between separators,
  shifting every field by one, so decoding always returned `tokens = nil`. Each
  request therefore fell back to a full bucket and no limit was ever enforced
  once state round-tripped through the dict. Only the in-process algorithm
  functions behaved correctly, which is why the unit tests passed.

## [0.1.0] - 2026-08-01

### Added

- Initial release.

[Unreleased]: https://github.com/fabiocicerchia/nginx-lua-waf-kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/fabiocicerchia/nginx-lua-waf-kit/releases/tag/v0.1.0
