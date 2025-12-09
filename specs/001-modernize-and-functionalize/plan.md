# Implementation Plan: Modernize and Functionalize Audio Library

**Branch**: `001-modernize-and-functionalize` | **Date**: 2025-09-28 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-modernize-and-functionalize/spec.md`

## Execution Flow (/plan command scope)
```
1. Load feature spec from Input path
   → If not found: ERROR "No feature spec at {path}"
2. Fill Technical Context (scan for NEEDS CLARIFICATION)
   → Detect Project Type from context (web=frontend+backend, mobile=app+api)
   → Set Structure Decision based on project type
3. Fill the Constitution Check section based on the content of the constitution document.
4. Evaluate Constitution Check section below
   → If violations exist: Document in Complexity Tracking
   → If no justification possible: ERROR "Simplify approach first"
   → Update Progress Tracking: Initial Constitution Check
5. Execute Phase 0 → research.md
   → If NEEDS CLARIFICATION remain: ERROR "Resolve unknowns"
6. Execute Phase 1 → contracts, data-model.md, quickstart.md, agent-specific template file (e.g., `CLAUDE.md` for Claude Code, `.github/copilot-instructions.md` for GitHub Copilot, `GEMINI.md` for Gemini CLI, `QWEN.md` for Qwen Code or `AGENTS.md` for opencode).
7. Re-evaluate Constitution Check section
   → If new violations: Refactor design, return to Phase 1
   → Update Progress Tracking: Post-Design Constitution Check
8. Plan Phase 2 → Describe task generation approach (DO NOT create tasks.md)
9. STOP - Ready for /tasks command
```

**IMPORTANT**: The /plan command STOPS at step 7. Phases 2-4 are executed by other commands:
- Phase 2: /tasks command creates tasks.md
- Phase 3-4: Implementation execution (manual or via tools)

## Summary
Primary requirement: Modernize podcast audio streaming library with protocol-based functional architecture using Swift 6 concurrency, Combine reactive patterns, and atomic operations. Technical approach: Incremental migration from existing Swift AudioToolbox/AVFoundation implementation to functional programming with protocol layers, maintaining backwards compatibility while enabling progressive API adoption.

## Technical Context
**Language/Version**: Swift 6.0 with strict concurrency enabled
**Primary Dependencies**: AVFoundation, AudioToolbox, Combine, swift-collections, swift-atomics
**Storage**: Local file downloads, no persistent database required
**Testing**: XCTest with contract tests, integration tests, performance tests
**Target Platform**: iOS 15+, tvOS 15+, macOS 12+ (cross-Apple platform)
**Project Type**: single - Swift Package Manager library targeting Apple platforms
**Performance Goals**: Sub-2% CPU usage during playback, <3 second streaming start time
**Constraints**: Memory leak prevention, backwards compatibility, App Store guidelines compliance
**Scale/Scope**: Podcast library for developers - protocol layers from simple to advanced APIs

## Constitution Check
*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

**I. Functional Programming**: ✅ PASS - Design uses protocol-oriented functional patterns with immutable data structures, pure functions, and type-driven design
**II. Reactive Architecture & Loose Coupling**: ✅ PASS - Current AudioUpdates Combine hub provides reactive coordination, existing loose coupling maintained
**III. Test-Driven Development**: ✅ PASS - Contract and integration tests exist, TDD approach for new features
**IV. Performance First**: ✅ PASS - Swift Atomics for lock-free operations, sub-2% CPU requirements
**V. Cross-Apple Platform**: ✅ PASS - iOS 15+, tvOS 15+, macOS 12+ support with conditional compilation
**VI. Backwards Compatibility**: ✅ PASS - Migration guides exist, incremental protocol adoption maintains existing APIs
**VII. Incremental Development**: ✅ PASS - Plan follows atomic task methodology, build-pass-after-each-change principle

## Project Structure

### Documentation (this feature)
```
specs/001-modernize-and-functionalize/
├── plan.md              # This file (/plan command output)
├── research.md          # Phase 0 output (/plan command)
├── data-model.md        # Phase 1 output (/plan command)
├── quickstart.md        # Phase 1 output (/plan command)
├── contracts/           # Phase 1 output (/plan command)
└── tasks.md             # Phase 2 output (/tasks command - NOT created by /plan)
```

### Source Code (repository root)
```
# Option 1: Single project (DEFAULT)
Source/
├── Models/
├── Protocols/
├── Implementations/
├── Engine/
├── Extensions/
├── Migration/
└── Util/

Tests/
├── Contracts/
├── Integration/
├── Performance/
└── Unit/
```

**Structure Decision**: Option 1 (Single project) - Swift Package Manager library with existing Source/ structure

## Phase 0: Outline & Research
1. **Extract unknowns from Technical Context** above:
   - No NEEDS CLARIFICATION found - all technical context resolved

2. **Generate and dispatch research agents**:
   ```
   Research Task: "Protocol-oriented functional patterns for audio streaming libraries"
   Research Task: "Swift 6 actor isolation patterns for real-time audio processing"
   Research Task: "Combine reactive patterns for audio state management best practices"
   Research Task: "Cross-platform audio development patterns for iOS/tvOS/macOS"
   Research Task: "Progressive API design patterns for libraries with simple-to-advanced protocol layers"
   ```

3. **Consolidate findings** in `research.md` using format:
   - Decision: [what was chosen]
   - Rationale: [why chosen]
   - Alternatives considered: [what else evaluated]

**Output**: research.md with protocol design patterns and reactive architecture decisions

## Phase 1: Design & Contracts
*Prerequisites: research.md complete*

1. **Extract entities from feature spec** → `data-model.md`:
   - AudioSession (state, progress, metadata)
   - DownloadTask (progress tracking, completion)
   - PlaybackState (playing, paused, buffering, completed, error)
   - AudioMetadata (title, duration, artwork, chapters)
   - Protocol hierarchy (basic to advanced layers)

2. **Generate API contracts** from functional requirements:
   - Basic playback protocol contract (play, pause, seek)
   - Advanced protocol contracts (effects, queue management, configuration)
   - Reactive updates contract (state, progress, download status)
   - Output protocol definitions to `/contracts/`

3. **Generate contract tests** from contracts:
   - One test file per protocol
   - Assert protocol conformance and behavior
   - Tests must fail (no implementation yet)

4. **Extract test scenarios** from user stories:
   - Simple 3-line streaming integration test
   - Protocol progressive adoption test
   - Backwards compatibility migration test

5. **Update agent file incrementally** (O(1) operation):
   - Run `.specify/scripts/bash/update-agent-context.sh claude`
     **IMPORTANT**: Execute it exactly as specified above. Do not add or remove any arguments.
   - Add protocol design patterns to CLAUDE.md
   - Update with Swift 6 concurrency patterns
   - Keep under 150 lines for token efficiency

**Output**: data-model.md, /contracts/*, failing tests, quickstart.md, CLAUDE.md update

## Phase 2: Task Planning Approach
*This section describes what the /tasks command will do - DO NOT execute during /plan*

**Task Generation Strategy**:
- Load `.specify/templates/tasks-template.md` as base
- Generate tasks from Phase 1 design docs (contracts, data model, quickstart)
- Each protocol contract → contract test task [P]
- Each entity → model refinement task [P]
- Each user story → integration test task
- Implementation tasks to make tests pass
- **CRITICAL**: Each task MUST be atomic - build passes after completion
- Complex modernizations MUST be decomposed into smallest possible increments

**Ordering Strategy**:
- TDD order: Tests before implementation
- Dependency order: Models before protocols before implementations
- Mark [P] for parallel execution (independent files)
- **Incremental Principle**: Each task independently verifiable via successful build
- No task should modify multiple subsystems simultaneously

**Estimated Output**: 20-25 numbered, ordered, atomic tasks in tasks.md

**IMPORTANT**: This phase is executed by the /tasks command, NOT by /plan

**Incremental Implementation Requirements**:
- All tasks MUST be atomic and independently verifiable
- Build success is the primary validation gate for each task
- No task should span multiple files unless absolutely necessary
- Complex refactoring MUST be broken into micro-increments
- Constitutional Principle VII (Incremental Development) MUST be followed

## Phase 3+: Future Implementation
*These phases are beyond the scope of the /plan command*

**Phase 3**: Task execution (/tasks command creates tasks.md)
**Phase 4**: Incremental Implementation (execute tasks.md following constitutional principles)
- Each task MUST result in a passing build before proceeding to next task
- If any task breaks the build, immediate reversion is REQUIRED
- Re-approach with smaller increments if build failures occur
- Use feature flags/conditional compilation to maintain stability during transitions
**Phase 5**: Validation (run tests, execute quickstart.md, performance validation)

## Complexity Tracking
*Fill ONLY if Constitution Check has violations that must be justified*

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| None | N/A | All constitutional principles satisfied |

## Progress Tracking
*This checklist is updated during execution flow*

**Phase Status**:
- [x] Phase 0: Research complete (/plan command)
- [x] Phase 1: Design complete (/plan command)
- [x] Phase 2: Task planning complete (/plan command - describe approach only)
- [ ] Phase 3: Tasks generated (/tasks command)
- [ ] Phase 4: Implementation complete
- [ ] Phase 5: Validation passed

**Gate Status**:
- [x] Initial Constitution Check: PASS
- [x] Post-Design Constitution Check: PASS
- [x] All NEEDS CLARIFICATION resolved
- [x] Complexity deviations documented

---
*Based on Constitution v1.1.0 - See `/memory/constitution.md`*
*Constitutional Principle VII (Incremental Development) enforced throughout*