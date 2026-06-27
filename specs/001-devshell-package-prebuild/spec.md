# Feature Specification: Pre-install devShell Packages at Build Time

**Feature Branch**: `001-devshell-package-prebuild`

**Created**: 2026-06-25

**Status**: Draft

**Input**: User description: "When an agentbox module is created, if the user specifies during build time, the build should download the remote repository (or look at the mounted repository, or whatever the installation method is) and detect whether it contains a Nix flake with a devShell. If a devShell is present, extract the packages declared in that devShell and install them into the virtual machine during build time. That way, when users enter the virtual machine and activate the dev flake, all dependencies are already installed in the VM and they don't have to download and install them."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pre-bake project devShell dependencies into the VM (Priority: P1)

A developer (or an AI coding agent) configures an agentbox VM for a project whose repository contains a Nix flake that defines a development shell (`devShell`). They opt in to the pre-install behavior when defining the VM. When the VM is built, agentbox locates the project's flake, reads the packages the devShell declares, and bakes those packages into the VM image as globally installed packages. When the user later enters the VM, every dependency is already present on the command path — they don't need to download anything or even activate the flake to use the tools.

**Why this priority**: This is the entire point of the feature — turning a slow, network-dependent first `nix develop` inside the VM into tools that are simply present and ready the moment the VM boots, offline included. Without this, the feature delivers no value.

**Independent Test**: Configure a VM with the pre-install option enabled and a project flake whose devShell declares a known, distinctive package. Build the VM, boot it with networking disabled, and confirm the declared package is available on the command path without any downloads.

**Acceptance Scenarios**:

1. **Given** a project repository containing a flake with a devShell that declares packages, **When** the user enables the pre-install option and builds the VM, **Then** the build completes successfully and the devShell's declared packages are present in the VM.
2. **Given** a built VM whose devShell packages were pre-installed, **When** the user enters the VM, **Then** the declared packages are available on the command path without the user activating the project's flake.
3. **Given** a built VM whose devShell packages were pre-installed, **When** the user enters the VM with no network access, **Then** the declared packages are available and, if the user does activate the project's development environment, activation fetches and builds nothing.

---

### User Story 2 - Opt-in, with safe default behavior (Priority: P2)

A developer creates an agentbox VM for a project that either has no flake, has a flake without a devShell, or is not one they want pre-baked. They expect agentbox to behave exactly as it does today unless they explicitly opt in to the pre-install behavior. When they do opt in but the project has no detectable devShell, the build should not silently produce a broken or confusingly incomplete VM.

**Why this priority**: The behavior must be backward compatible and predictable. Existing users and configurations must be unaffected, and opting in must never make a VM harder to reason about than not opting in.

**Independent Test**: Build a VM for a project with no flake (a) without the option and (b) with the option enabled; confirm (a) is unchanged from today and (b) completes with a clear, observable indication that no devShell was found.

**Acceptance Scenarios**:

1. **Given** the pre-install option is not enabled, **When** the VM is built, **Then** behavior is identical to current agentbox behavior and no devShell inspection occurs.
2. **Given** the pre-install option is enabled but the project contains no flake or no devShell, **When** the VM is built, **Then** the build outcome is unambiguous to the user (either a clear failure or a clear, surfaced notice that nothing was pre-installed) rather than a silent no-op.

---

### User Story 3 - Visibility into what was pre-installed (Priority: P3)

A developer who enabled the pre-install behavior wants to confirm which packages were detected from the devShell and baked into the VM, so they can trust the result and debug mismatches (for example, when activation still tries to fetch something they expected to be cached).

**Why this priority**: Trust and debuggability. Pre-installing dependencies that the user cannot see or verify makes failures hard to diagnose, but the core value (faster activation) is delivered without it.

**Independent Test**: Enable the option for a project with a known devShell, build the VM, and confirm there is a discoverable record of which packages were extracted and pre-installed.

**Acceptance Scenarios**:

1. **Given** the pre-install option is enabled and a devShell was detected, **When** the VM is built, **Then** the set of packages that were extracted and pre-installed is observable to the user.

---

### Edge Cases

- **No flake present**: The project source contains no flake at the expected location → resolved per Story 2 (clear failure or surfaced notice; never a silent broken VM).
- **Flake without a devShell**: A flake exists but declares no development shell → treated the same as "no devShell detected."
- **Multiple devShells**: A flake declares more than one development shell (a default plus named variants) → the build needs a defined rule for which shell(s) to extract.
- **devShell that cannot be evaluated**: The flake's devShell references a definition that fails to evaluate or resolve → the build must fail clearly rather than partially baking the VM.
- **Source not available at build time**: The project uses a delivery method (`mount` or `copy`) whose contents are only populated after the VM boots → the build must clearly report that pre-install is unavailable for that delivery method (only `git` is supported).
- **Private repository**: The project flake lives in a private repository that requires credentials to fetch at build time → the build needs a defined, secure behavior (succeed with provided credentials, or fail clearly).
- **Large dependency set**: The devShell declares a very large dependency closure → the VM image grows accordingly; the user should be able to anticipate this.
- **Stale pre-install**: The project's devShell changes after the VM was built → the pre-installed set reflects the state at build time until the VM is rebuilt.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide an explicit, opt-in setting on an agentbox VM configuration that enables pre-installing a project's devShell packages at build time. When the setting is not enabled, build behavior MUST be unchanged from current behavior.
- **FR-002**: When the setting is enabled, the system MUST locate the project's flake from the configured project source at build time and determine whether that flake declares a development shell.
- **FR-003**: When a development shell is detected, the system MUST determine the set of packages that shell makes available.
- **FR-004**: When a development shell is detected, the system MUST add its declared packages to the VM's globally installed packages so they are available on the command path inside the VM immediately, without the user needing to activate the project's flake. Because these packages are baked into the VM image, the user MUST NOT need to download or build them after boot, and activating the project's development environment MUST NOT re-fetch or rebuild them.
- **FR-005**: The pre-install behavior MUST be supported for the `git` project source type, where the repository can be fetched and evaluated at build time. For project source types whose contents are only populated after the VM boots (`mount` and `copy`), the system MUST clearly report that pre-install is unavailable rather than silently skipping it.
- **FR-006**: When the setting is enabled but no flake or no devShell is detected, the system MUST surface this outcome to the user unambiguously rather than producing a silent no-op or a confusingly incomplete VM.
- **FR-007**: When a devShell is detected but its packages cannot be evaluated or resolved, the system MUST fail the build with a clear error rather than producing a partially pre-installed VM.
- **FR-008**: When a flake declares more than one development shell, the system MUST apply a defined, documented rule for which shell is used (defaulting to the flake's default/primary development shell) and MUST allow the user to select a specific named shell.
- **FR-009**: The system MUST make the set of packages it extracted and pre-installed observable to the user, so they can verify and debug the result.
- **FR-010**: The packages activating the development environment relies on MUST match the packages that were pre-installed, so that activation does not re-fetch equivalent dependencies due to a mismatch.
- **FR-011**: Enabling the setting MUST NOT change the VM's runtime project-source behavior (mount/copy/git remain as configured); it only affects what is pre-baked into the image at build time.

### Key Entities *(include if data involved)*

- **Project flake**: The Nix flake belonging to the user's project, identified within the project source. Source of the development shell definition.
- **devShell (development shell)**: The development environment declared by the project flake. May be a single default shell or one of several named shells. Holds the list of packages a developer needs to work on the project.
- **Extracted package set**: The concrete collection of packages derived from the selected devShell, which is the unit that gets pre-installed into the VM and reported back to the user.
- **VM configuration / agentbox module**: The declarative definition of the VM, where the user opts in to the pre-install behavior and (optionally) selects which devShell to use.
- **Built VM image**: The artifact produced by the build, into which the extracted package set is baked.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: With the option enabled for a project whose devShell declares packages, the declared packages are available on the command path inside the freshly booted VM with zero packages downloaded or built (verifiable by booting with networking disabled).
- **SC-002**: Getting the project's tools ready to use inside a pre-installed VM is substantially faster than in a VM built without the option, because the tools are present at boot instead of being downloaded/built on first use.
- **SC-003**: 100% of builds where the option is left disabled produce results identical to current agentbox behavior (no regression).
- **SC-004**: When the option is enabled and a devShell is present, 100% of the packages the devShell declares are present in the VM after build (none silently dropped).
- **SC-005**: When the option is enabled and no devShell is found, the user can determine that fact from the build outcome in 100% of cases (no silent no-op).
- **SC-006**: A user can enumerate the exact set of packages that were pre-installed from the devShell after a successful build.

## Assumptions

- The behavior is **opt-in**; the default agentbox build is unchanged. This preserves backward compatibility for all existing configurations.
- The extracted devShell packages are installed as **globally available** packages in the VM, so they are on the command path the moment the VM boots; the user does not need to activate the project's flake to use them. Activating the flake remains possible and, because the packages are already baked in, needs no network access.
- Pre-install is supported only for the **`git`** project source type at build time. For `mount` and `copy` sources, whose contents are populated only after boot, the build clearly reports that pre-install is unavailable.
- When multiple development shells exist and the user does not select one, the flake's **default/primary** development shell is used.
- If the project's devShell changes after the VM is built, the pre-installed contents reflect the devShell as it was **at build time**; refreshing requires a rebuild. Keeping the pre-installed set continuously in sync with a changing devShell is out of scope.
- The size of the VM image will grow in proportion to the devShell's dependency closure; users opting in accept this trade-off in exchange for faster, offline activation.
- For private project repositories, fetching the flake at build time relies on credentials the user already supplies through existing agentbox mechanisms; introducing new credential-handling flows is out of scope for this feature.
- Detecting and pre-installing dependencies that are **not** expressed through the project's flake devShell (e.g. language-ecosystem lockfiles, Dockerfiles) is out of scope; this feature is specifically about the Nix flake devShell.
