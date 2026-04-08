# Agentbox Agent Skill

## Overview

Create an agent skill that instructs AI coding agents how to autonomously use agentbox to create, configure, and run isolated NixOS VM development environments. The skill should be installable via `npx skills add gotha/agentbox`.

## Goals

- Enable AI agents to autonomously spin up isolated VM environments for safe code execution
- Provide clear decision-making guidance for common agentbox workflows
- Support multiple AI coding agents (Claude Code, Cursor, Augment, Codex, etc.)
- Make the skill discoverable and installable via the standard `npx skills` CLI

## Design Decisions

The following decisions were made through a Q&A refinement process:

| # | Topic | Decision |
|---|-------|----------|
| 1 | Target audience | AI agents themselves (autonomous usage) |
| 2 | Workflow | Create project-specific VM, maintain config over time |
| 3 | Flake location | Agent decides; default to `.agentbox/`, can merge with existing root flake |
| 4 | Source type | Git (SSH clone) if remote exists, Copy if no git, Mount only if user requests |
| 5 | Getting changes back | Git workflow (commit & push from inside VM) |
| 6 | Credential sharing | Always share `~/.ssh` AND `~/.gitconfig` for git source type |
| 7 | AI tools in VM | Always enable matching tool with `syncConfigFromHost` |
| 8 | Interaction model | Hybrid: SSH for simple tasks, AI tool inside VM for complex work |
| 9 | VM lifecycle | Keep running (user shuts down manually) |
| 10 | Reuse existing VM | Ask user whether to reuse or start fresh |
| 11 | Prerequisites missing | Guide with step-by-step instructions, wait for confirmation |
| 12 | Docker support | Auto-detect from project files (Dockerfile, docker-compose.yml) |
| 13 | Additional packages | Auto-detect from project files (package.json → node, go.mod → go, etc.) |
| 14 | Config updates | Automatic as project evolves |
| 15 | Rebuild after changes | Inform user, let them decide when to rebuild |
| 16 | Port forwarding | Use SSH tunneling (`ssh -L`) on demand, not static QEMU ports |
| 17 | Instruction style | High-level guidance with key commands as examples |
| 18 | Handling failures | Try simple fixes, escalate quickly if not obvious |
| 19 | Repo examples | Reference examples in `examples/` directory |
| 20 | When NOT to use | GUI apps, direct hardware/GPU access, production deployments |
| 21 | VM naming | Project-based (e.g., `myproject-vm`) |
| 22 | Readiness detection | Poll SSH until connection succeeds |
| 23 | Cleanup guidance | Include instructions for cleanup |

## Skill Specification

### File Location

```
skills/agentbox/SKILL.md
```

### YAML Frontmatter

```yaml
---
name: agentbox
description: Create and run isolated NixOS VM development environments for safe code execution, testing, and sandboxed AI agent workflows
version: 1.0.0
author: gotha
category: Development
tags:
  - vm
  - sandbox
  - nix
  - nixos
  - isolation
  - development
  - testing
  - docker
platforms:
  - claude-code
  - cursor
  - augment
  - codex
  - opencode
  - cline
  - roo
  - windsurf
  - github-copilot
---
```

## Skill Content Structure

### 1. Introduction & When to Use
- What agentbox is: isolated NixOS VMs for safe code execution
- Primary use case: autonomous agent workflows requiring isolation
- When NOT to use: GUI apps, GPU/hardware access, production deployments

### 2. Prerequisites Check
- Nix package manager with flakes enabled
- Linux builder for macOS (nix-darwin or Determinate Nix)
- If missing: provide step-by-step installation guide, wait for user confirmation

### 3. Project Analysis & Setup
- Check for existing `.agentbox/` directory or root `flake.nix`
- Determine source type:
  - Has git remote? → Use `git` source (SSH clone)
  - No git remote? → Use `copy` source
  - User explicitly requests? → Use `mount` source
- Auto-detect required packages from project files
- Auto-detect Docker needs from Dockerfile/docker-compose.yml

### 4. Flake Configuration
- Default location: `.agentbox/flake.nix`
- Alternative: merge with existing root `flake.nix` if appropriate
- VM naming: `{project-name}-vm`
- Always share `~/.ssh` and `~/.gitconfig` for git source
- Always enable matching AI tool with `syncConfigFromHost`

### 5. VM Lifecycle Management
- Starting: `nix run .#vm` from flake directory
- Readiness: Poll SSH until connection succeeds
- Reuse: If VM already running, ask user whether to reuse or start fresh
- Shutdown: User manually shuts down (Ctrl+A X or explicit shutdown)

### 6. Working Inside the VM
- Simple tasks: SSH commands from host (`ssh dev@localhost -p <PORT> "command"`)
- Complex tasks: Use AI tool running inside the VM
- Port access: Use SSH tunneling (`ssh -L localport:localhost:remoteport`)
- Getting changes back: Commit and push via git from inside VM

### 7. Configuration Evolution
- Monitor project changes (new dependencies, tools)
- Automatically update flake.nix when project needs change
- Inform user when rebuild is needed, let them decide when

### 8. Error Handling
- Try simple fixes first (missing package → add to flake)
- Escalate quickly to user if fix isn't obvious
- Provide clear error context and suggested solutions

### 9. Cleanup
- Removing `.agentbox/` directory
- Cleaning Nix store with `nix-collect-garbage`
- Removing VM disk images

### 10. Reference
- Link to examples in `examples/` directory
- Link to full agentbox documentation

## Implementation Plan

### Phase 1: Create Skill File
1. Create `skills/agentbox/` directory
2. Create `SKILL.md` with YAML frontmatter and all sections

### Phase 2: Test Installation
1. Test with `npx skills add .` from repo root
2. Verify skill appears in `npx skills list`
3. Test with multiple agents

## Files to Create

| File | Description |
|------|-------------|
| `skills/agentbox/SKILL.md` | Main skill file with agent instructions |

## Success Criteria

- [ ] SKILL.md created with valid frontmatter
- [ ] All decision points from Q&A documented
- [ ] Clear conditional logic for source type selection
- [ ] Package auto-detection guidance included
- [ ] Examples reference `examples/` directory
- [ ] Skill installable via `npx skills add gotha/agentbox`

## Package Auto-Detection Patterns

The skill should instruct the agent to detect packages based on:

| File | Packages to Add |
|------|-----------------|
| `package.json` | `nodejs`, `npm` (or `yarn`/`pnpm` if lockfile present) |
| `go.mod` | `go`, `gopls` |
| `Cargo.toml` | `rustc`, `cargo`, `rust-analyzer` |
| `requirements.txt` / `pyproject.toml` | `python3`, `pip` |
| `Gemfile` | `ruby`, `bundler` |
| `mix.exs` | `elixir`, `erlang` |
| `build.gradle` / `pom.xml` | `jdk`, `gradle` or `maven` |
| `Makefile` | `gnumake` |
| `CMakeLists.txt` | `cmake`, `gcc` |

## Source Type Decision Logic

```
IF project has git remote (check with `git remote -v`)
  → Use source.type = "git" with SSH URL
  → Share ~/.ssh and ~/.gitconfig via hostShares
ELSE IF project has .git directory but no remote
  → Use source.type = "copy"
ELSE IF user explicitly requests live sync
  → Use source.type = "mount"
ELSE
  → Use source.type = "copy"
```

## VM Readiness Polling

```bash
# Poll until SSH succeeds (with timeout)
PORT=$(cat /tmp/{vm-name}-ssh-port)
until ssh -o ConnectTimeout=2 -o StrictHostKeyChecking=no dev@localhost -p $PORT true 2>/dev/null; do
  sleep 2
done
```
