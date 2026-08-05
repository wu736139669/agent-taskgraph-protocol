# Agent TaskGraph Plugin Package

This directory is the platform-ready package for the `agent-taskgraph` Skill. The repository root remains the canonical source; this directory is a versioned distribution copy with host-specific manifests.

## Package contents

| Path | Purpose |
|---|---|
| `.codex-plugin/plugin.json` | OpenAI/Codex skills-only manifest |
| `.claude-plugin/plugin.json` | Claude Code plugin manifest |
| `skills/agent-taskgraph/` | Self-contained Skill, templates, initializer, workers, and update checker |
| `LICENSE` | Apache-2.0 license for this package |

The package version is `0.8.0-beta.2`. Before a release, keep it equal to the root [`VERSION`](../../VERSION), the Skill [`VERSION`](skills/agent-taskgraph/VERSION), and the Git tag.

## Local validation

Run from the repository root:

```bash
python3 "${CODEX_HOME:-$HOME/.codex}/skills/.system/plugin-creator/scripts/validate_plugin.py" \
  plugins/agent-taskgraph
claude plugin validate ./plugins/agent-taskgraph
```

The first command validates the Codex package manifest and layout. The second validates the Claude Code manifest. Both commands are release-preparation checks; they do not publish the package.

To try the Claude package in a local session:

```bash
claude --plugin-dir ./plugins/agent-taskgraph
```

For Codex or a directory-based installer, the canonical repository remains the easiest path:

```bash
npx skills add wu736139669/agent-taskgraph-protocol --skill agent-taskgraph
```

## Submission status

The package is prepared for review but has not been accepted into the OpenAI/Codex Plugin Directory or the Claude Code community marketplace. Submit through the platform's current publisher workflow after reviewing the root [release notes](https://github.com/wu736139669/agent-taskgraph-protocol/releases).

Do not create a second repository for a platform submission. Use this package as the submission artifact and keep GitHub tags as the version authority.

## Updates

Standalone Git and symlink installs use the root `./install.sh --check-update` command. Plugin hosts manage marketplace update notices themselves. An active frozen batch keeps the protocol version recorded in its project `PROJECT.md`; it does not switch versions mid-batch.

## Synchronization rule

The root `SKILL.md`, templates, workers, and scripts are canonical. When they change, copy the intended release contents into `skills/agent-taskgraph/`, update all version files and manifests together, run `./tests/smoke.sh`, then create a new Git tag. The smoke test checks the copied Skill and package metadata for drift.
