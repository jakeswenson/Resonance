# Tasks: Modernize and Functionalize Audio Library

**Input**: Design documents from `/specs/001-modernize-and-functionalize/`
**Prerequisites**: plan.md, research.md, data-model.md, contracts/, quickstart.md

## Execution Flow (main)
```
1. Load plan.md from feature directory ✅
   → Extract: Swift 6, AVFoundation/Combine, protocol-oriented design
2. Load design documents ✅:
   → data-model.md: AudioSession, PlaybackState, AudioMetadata, DownloadTask entities
   → contracts/: 6 protocol files → 6 contract test tasks
   → research.md: Progressive protocol hierarchy, actor patterns
   → quickstart.md: Integration scenarios, performance validation
3. Generate tasks by category:
   → Setup: Swift Package Manager, dependencies, protocols
   → Tests: 6 contract tests, 4 integration tests
   → Core: 5 protocol implementations, 4 data models, reactive coordinator
   → Integration: Actor coordination, Combine integration
   → Polish: performance tests, migration guides, documentation
4. Apply task rules:
   → Different files = mark [P] for parallel
   → Same file = sequential (no [P])
   → Tests before implementation (TDD)
   → **CONSTITUTIONAL RULE VII**: Each task MUST be atomic - build passes after completion
5. Number tasks sequentially (T001-T027)
6. All contracts have tests ✅, all entities have models ✅
7. Ready for execution
```

## Format: `[ID] [P?] Description`
- **[P]**: Can run in parallel (different files, no dependencies)
- Include exact file paths in descriptions
- **ATOMIC REQUIREMENT**: Each task MUST result in passing build
- **REVERT RULE**: If task breaks build, immediately revert and re-approach with smaller increments

## Path Conventions
- **Single project**: `Source/`, `Tests/` at repository root (Swift Package Manager)
- All paths are absolute from repository root
- Protocol files in `Source/Protocols/`
- Implementation files in `Source/Implementations/`
- Model files in `Source/Models/`

## Phase 3.1: Setup
- [ ] T001 Create protocol directory structure in Source/Protocols/
- [ ] T002 [P] Update Package.swift with modern Swift 6 concurrency settings
- [ ] T003 [P] Create basic AudioError enum in Source/Models/AudioError.swift

## Phase 3.2: Tests First (TDD) ⚠️ MUST COMPLETE BEFORE 3.3
**CRITICAL: These tests MUST be written and MUST FAIL before ANY implementation**
- [ ] T004 [P] Contract test AudioPlayable protocol in Tests/Contracts/AudioPlayableTests.swift
- [ ] T005 [P] Contract test AudioConfigurable protocol in Tests/Contracts/AudioConfigurableTests.swift
- [ ] T006 [P] Contract test AudioEffectable protocol in Tests/Contracts/AudioEffectableTests.swift
- [ ] T007 [P] Contract test AudioQueueManageable protocol in Tests/Contracts/AudioQueueManageableTests.swift
- [ ] T008 [P] Contract test AudioDownloadable protocol in Tests/Contracts/AudioDownloadableTests.swift
- [ ] T009 [P] Contract test AudioEngineAccessible protocol in Tests/Contracts/AudioEngineAccessibleTests.swift
- [ ] T010 [P] Integration test basic 3-line streaming in Tests/Integration/BasicPlaybackIntegrationTests.swift
- [ ] T011 [P] Integration test progressive protocol adoption in Tests/Integration/ProtocolProgressionTests.swift
- [ ] T012 [P] Integration test backwards compatibility in Tests/Integration/BackwardsCompatibilityTests.swift
- [ ] T013 [P] Performance test CPU usage <2% in Tests/Performance/CPUUsageTests.swift

## Phase 3.3: Core Implementation (ONLY after tests are failing)
### Data Models
- [ ] T014 [P] AudioSession model in Source/Models/AudioSession.swift
- [ ] T015 [P] PlaybackState enum in Source/Models/PlaybackState.swift
- [ ] T016 [P] AudioMetadata struct in Source/Models/AudioMetadata.swift
- [ ] T017 [P] DownloadTask model in Source/Models/DownloadTask.swift

### Protocol Definitions
- [ ] T018 [P] AudioPlayable protocol definition in Source/Protocols/AudioPlayable.swift
- [ ] T019 [P] AudioConfigurable protocol definition in Source/Protocols/AudioConfigurable.swift
- [ ] T020 [P] AudioEffectable protocol definition in Source/Protocols/AudioEffectable.swift
- [ ] T021 [P] AudioQueueManageable protocol definition in Source/Protocols/AudioQueueManageable.swift
- [ ] T022 [P] AudioDownloadable protocol definition in Source/Protocols/AudioDownloadable.swift

### Basic Implementations
- [ ] T023 BasicAudioPlayer implementation conforming to AudioPlayable in Source/Implementations/BasicAudioPlayer.swift
- [ ] T024 EnhancedAudioPlayer implementation conforming to AudioConfigurable in Source/Implementations/EnhancedAudioPlayer.swift
- [ ] T025 ReactiveAudioCoordinator actor for state management in Source/Implementations/ReactiveAudioCoordinator.swift

## Phase 3.4: Integration
- [ ] T026 AudioUpdates reactive hub integration with new protocols in Source/AudioUpdates.swift
- [ ] T027 Cross-platform conditional compilation for AudioSessionActor in Source/Implementations/AudioSessionActor.swift

## Dependencies
- Setup (T001-T003) before everything
- Tests (T004-T013) before implementation (T014-T027)
- Data models (T014-T017) before protocol implementations (T018-T022)
- Protocol definitions (T018-T022) before basic implementations (T023-T025)
- Basic implementations (T023-T025) before integration (T026-T027)

## Parallel Execution Examples

### Phase 3.2: Contract Tests (All Parallel)
```bash
# Launch T004-T009 together (contract tests):
Task: "Contract test AudioPlayable protocol in Tests/Contracts/AudioPlayableTests.swift"
Task: "Contract test AudioConfigurable protocol in Tests/Contracts/AudioConfigurableTests.swift"
Task: "Contract test AudioEffectable protocol in Tests/Contracts/AudioEffectableTests.swift"
Task: "Contract test AudioQueueManageable protocol in Tests/Contracts/AudioQueueManageableTests.swift"
Task: "Contract test AudioDownloadable protocol in Tests/Contracts/AudioDownloadableTests.swift"
Task: "Contract test AudioEngineAccessible protocol in Tests/Contracts/AudioEngineAccessibleTests.swift"
```

### Phase 3.2: Integration Tests (All Parallel)
```bash
# Launch T010-T013 together (integration tests):
Task: "Integration test basic 3-line streaming in Tests/Integration/BasicPlaybackIntegrationTests.swift"
Task: "Integration test progressive protocol adoption in Tests/Integration/ProtocolProgressionTests.swift"
Task: "Integration test backwards compatibility in Tests/Integration/BackwardsCompatibilityTests.swift"
Task: "Performance test CPU usage <2% in Tests/Performance/CPUUsageTests.swift"
```

### Phase 3.3: Data Models (All Parallel)
```bash
# Launch T014-T017 together (data models):
Task: "AudioSession model in Source/Models/AudioSession.swift"
Task: "PlaybackState enum in Source/Models/PlaybackState.swift"
Task: "AudioMetadata struct in Source/Models/AudioMetadata.swift"
Task: "DownloadTask model in Source/Models/DownloadTask.swift"
```

### Phase 3.3: Protocol Definitions (All Parallel)
```bash
# Launch T018-T022 together (protocol definitions):
Task: "AudioPlayable protocol definition in Source/Protocols/AudioPlayable.swift"
Task: "AudioConfigurable protocol definition in Source/Protocols/AudioConfigurable.swift"
Task: "AudioEffectable protocol definition in Source/Protocols/AudioEffectable.swift"
Task: "AudioQueueManageable protocol definition in Source/Protocols/AudioQueueManageable.swift"
Task: "AudioDownloadable protocol definition in Source/Protocols/AudioDownloadable.swift"
```

## Notes
- [P] tasks = different files, no dependencies
- Verify tests fail before implementing
- **CRITICAL**: Build MUST pass after each task completion
- Commit after each task (only if build passes)
- If build breaks: immediate revert, decompose into smaller increments
- Constitutional Principle VII enforced: each task is atomic and independently verifiable

## Task Validation Checklist
*GATE: Checked before execution*

- [x] All 6 protocol contracts have corresponding test tasks
- [x] All 4 entities from data-model.md have model creation tasks
- [x] All tests come before implementation (TDD ordering)
- [x] Parallel tasks are truly independent (different files)
- [x] Each task specifies exact file path
- [x] No task modifies same file as another [P] task
- [x] **CONSTITUTIONAL COMPLIANCE**: Each task is atomic and independently verifiable
- [x] **BUILD SAFETY**: No task should risk breaking build across multiple systems
- [x] **INCREMENTAL DECOMPOSITION**: Complex protocol hierarchy broken into micro-increments

## Implementation Notes

### TDD Approach
1. All contract tests (T004-T009) must be written first and FAIL
2. All integration tests (T010-T013) must be written and FAIL
3. Only then begin implementation tasks (T014+)
4. Implementation tasks make the failing tests pass

### Constitutional Compliance
- Each task follows Principle VII (Incremental Development)
- Build must pass after completing each individual task
- No wholesale changes across multiple files in single task
- Immediate reversion required if any task breaks build

### Performance Validation
- T013 validates sub-2% CPU usage requirement
- Integration tests validate 3-line basic usage requirement
- Protocol progression tests validate progressive complexity adoption

### Cross-Platform Support
- T027 handles iOS/tvOS/macOS conditional compilation
- Protocol definitions remain platform-agnostic
- Implementation details use platform-specific code where needed

---
*Tasks generated: 2025-09-28*
*Total: 27 atomic, incremental tasks*
*Ready for execution following Constitutional Principle VII*