# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Made `gtask open` available outside Git, searching recursively below the
  current directory, and added `cwork`/`cvault` directory shortcuts.
- Added the `gr`, `dirty`, `why`, `handoff`, `standup`, and `focus` workflow
  utilities for repository navigation, filtered context handoff, local status summaries,
  and priority-first TODO selection without automatic AI invocation.
- Added an interactive Docker demo with a prepared sample repository
  and matching README, Markdown tutorial, and GitHub Pages instructions.

## [0.3.0] - 2026-09-02

### Added

- Added repository-local verification, open-source governance, licensing,
  repository hygiene, and issue forms.
- Added immutable-pinned macOS and Windows CI plus versioned, checksummed
  release packaging for the `0.3.0` preview.

### Fixed

- Corrected the changed-file picker for repositories without an initial commit.
- Corrected installation and diagnostic expectations for the required `fzf`
  dependency.

### Security

- Made non-interactive AI review fail closed unless the caller explicitly passes
  `--all`.
- Centralized filtering of sensitive paths before they are included in AI context.

## [0.2.1] - 2026-09-02

This release predates the maintained changelog; no earlier release history is
recorded here.
