# Native Windows Host support (#399)

## Findings and implementation

The reported home-probe failure is only the first Unix assumption. Windows
OpenSSH cannot forward herdr's native named-pipe endpoints with
direct-streamlocal, and herdr's raw PTY attach remains Unix-only.

herdr v0.9.3 already provides supported replacements: `remote-api-bridge`
for NDJSON API/Events and `terminal session control` for ANSI viewport frames,
raw input, semantic scrolling/mouse, resize, and release. No herdr patch,
WSL environment, extra service, or dependency is required. The pinned source
evidence and transport decision are in [ADR 0018](../adr/0018-native-windows-hosts.md).

The app now detects native Windows, probes USERPROFILE, runs encoded
PowerShell commands independently of cmd/PowerShell login-shell syntax,
filters startup chatter, and bounds all Windows SSH sessions together.
Default and named endpoints are resolved by herdr itself; explicit endpoint
overrides preserve the supplied path spelling. Request stdin remains open
until the response arrives. The terminal adapter restores modes and waits for
real SSH EOF before reading the remote exit status.

Windows directory browsing and launch selection accept drive/UNC paths.
Pairing, Changes, Skills, uploads, and notification registration are excluded
and refused explicitly. Their POSIX shell and permission assumptions require
separate work. Unix transport and offline discovery retain their existing
behavior, including known absolute endpoints that do not require HOME.

## Local verification

- `make test-app TEST_FLAGS='-only-testing:HeelerTests/<SuiteTypeName> ...'`
  selected 15 suites on the final implementation: **187 tests passed**.
  Suites: WindowsTerminalChannelTests, BootstrappedExecChannelTests,
  RemoteHostEnvironmentTests, RemoteHostPathTests, SSHChannelAdmissionTests,
  RemoteDirectoryBrowserTests, StartAgentStoreTests, NewTerminalStoreTests,
  HerdrSocketLocationTests, WakeCommandTests, TransportErrorPresentationTests,
  PreflightReportTests, SSHSourcePolicyTests, ComposerStagingStoreTests, and
  SkillsPaneStoreTests.
- `HEELER_CI_LANE=package HEELER_CI_SIMULATOR_UDID=<uuid> scripts/run-ci-ios-tests.sh`:
  **70/70 package tests passed, zero skips, exit 0**. This includes five new
  real SSH exec-stream tests: byte-preserving no-PTY output, 4 MiB stderr
  discard, timeout/cancellation reuse, idempotent close, and uncertain-open
  connection invalidation.
- `make test-ci-app HEELER_CI_SIMULATOR_UDID=<uuid>`: Session fixture **11
  passed, 2 password tests skipped** (no passwordless sudo); direct-streamlocal
  **9/9 passed**; shared fixture **115/115 passed**. This rerun proved the
  correction of premature Unix home probing during offline discovery.
- The broader app lane registered 2,461 tests: **2,321 passed, 3 failed,
  137 fixture tests skipped** (2,324 executed). It built before the final
  Windows endpoint-selection and unavailable-feature presentation refinements;
  those refinements passed the final 187-test selection above. The three
  failures were unchanged software-keyboard tests waiting for UIKit:
  `AgentDirectInputTests/composerAndDirectInputTransferVisibleKeyboardWithoutReloading()`,
  `TerminalAttachTests/aDroppedPresentationSettlesAgainstTheWindowsLiveKeyboardLayoutGuide()`,
  and `TerminalAttachTests/theComposerSettlesItsHandoffAgainstTheLiveKeyboardLayoutGuide()`.
  One keyboard case also timed out in isolation. No parent-revision run was
  performed, so this does not establish a passing or failing baseline.
- `git diff --check` and `bash -n scripts/run-ci-ios-tests.sh` passed.
  The Xcode project was regenerated through `make`.

These checks establish compilation, protocol/path behavior, and local SSH
lifecycle coverage. **Native Windows runtime acceptance has not been run.**
Use [the Windows checklist](../guides/native-windows-testing.md) for
DefaultShell, pipe, session isolation, input, resize, scrolling, and reconnect
acceptance. It also records the feature boundaries and separate outcomes.
