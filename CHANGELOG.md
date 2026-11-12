# Changelog

All notable changes to CatNotch. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow the project version (`MARKETING_VERSION`). Release assets and generated notes are on [Releases](https://github.com/thecharydev/catnotch/releases).

## [Unreleased]

### Added
- MIT license, contributing guide, code of conduct, security policy, issue and pull request templates.
- CodeQL analysis and Dependabot updates for GitHub Actions.

### Changed
- GitHub Actions are pinned to commit SHAs, and the release workflow only gets write access in its release job.

## [2.0.3] - 2026-11-12

### Added
- An update now installs first and stops at "installed", and a Restart now button restarts into the new version when you choose.

### Fixed
- The notch no longer stays hidden on other desktops after leaving a fullscreen app, and it hides over fullscreen apps that split their window in two, such as Ghostty.

## [2.0.0] - 2026-11-09

The native rewrite, and the Bridge release: it keeps the old `CatNotch-VERSION-universal-mac.zip` and `latest-mac.yml` names so installed 1.0.x apps can update to it.

### Changed
- CatNotch is now a native Swift and SwiftUI app. Electron is removed. See [ADR 0001](docs/adr/0001-rewrite-as-native-macos-app.md).
- Requires Apple silicon and macOS 14 or newer. Intel Macs and macOS 13 stay on 1.0.x.
- The first launch imports your DeskNotch settings once. macOS asks for permissions again once, because the app was renamed.

### Added
- A native notch panel per display with hover to open and click-through elsewhere, Default and Glass styles, and display rules.
- Focus timer, tasks, now playing, file shelf with screenshots, calendar and reminders, AI usage rings, system glance tiles, the cat companion and other characters.
- Claude Code on the notch: permission popups, questions, a session list and chat.
- In-app update from Settings.

## [1.0.8] - 2026-11-03

### Added
- Update CatNotch from Settings.

## [1.0.7] - 2026-11-02

### Removed
- Windows support. CatNotch is macOS only.

## [1.0.6] - 2026-10-31

### Added
- Renamed from DeskNotch to CatNotch, with a cat icon and a macOS release flow.
- Tests for the Claude hook server, and a CI test workflow.

### Fixed
- Hover behaviour on the notch.
- The macOS release no longer publishes through electron-builder.

[Unreleased]: https://github.com/thecharydev/catnotch/compare/2.0.0...HEAD
[2.0.0]: https://github.com/thecharydev/catnotch/compare/1.0.8...2.0.0
[1.0.8]: https://github.com/thecharydev/catnotch/compare/1.0.7...1.0.8
[1.0.7]: https://github.com/thecharydev/catnotch/compare/1.0.6...1.0.7
[1.0.6]: https://github.com/thecharydev/catnotch/releases/tag/1.0.6
