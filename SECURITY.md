# Security Policy

  ## Supported Versions

  This repository packages Tor binaries for use by Java projects, including Bisq.
  It contains platform-specific Tor binary artifacts and checksum metadata.

  Security fixes are applied to the active Bisq-maintained branch and any binary
  version currently used by supported Bisq applications.

  | Version / Branch | Supported |
  | --- | --- |
  | `master` | :white_check_mark: |
  | Current packaged Tor binary version used by supported Bisq applications | :white_check_mark: |
  | Active Tor upgrade branches while under review | :white_check_mark: |
  | Older packaged Tor versions, unsupported forks, or locally modified builds | :x: |

  Vulnerabilities in Tor itself should also be reported to the Tor Project
  according to its own security policy. This policy covers the Bisq-maintained
  packaging repository, including platform artifacts, checksums, dependency
  metadata, release/update workflow, and integration risk for Bisq applications.

  ## Reporting a Vulnerability

  Please do **not** report security vulnerabilities through public pull requests,
  Matrix rooms, forums, or social media.

  Report suspected vulnerabilities privately through GitHub's **Report a
  vulnerability** flow on this repository's Security page. If that option is not
  available, contact Bisq maintainers through the main Bisq project security
  channel and ask for a private reporting path. Do not include exploit details in
  public channels.

  Include as much detail as possible:

  - affected branch, commit, packaged Tor version, platform, architecture, and
    artifact name;
  - affected module, such as `tor-binary-linux64`, `tor-binary-linux32`,
    `tor-binary-macos`, `tor-binary-macos-aarch64`, `tor-binary-windows`,
    `tor-binary-windows64`, `tor-binary-geoip`, or `tor-binary-resources`;
  - whether the issue affects binary provenance, checksum verification, platform
    selection, packaging, file permissions, extraction behavior, dependency
    metadata, or build/release workflow;
  - whether the issue can lead to execution of a wrong or malicious Tor binary,
    IP leakage, Tor bypass, traffic deanonymization, unsafe update behavior, or
    supply-chain compromise;
  - reproduction steps, affected checksums, file hashes, artifact URLs, build logs,
    or proof of concept code where useful;
  - whether the issue depends on a compromised upstream binary, stale Tor version,
    incorrect checksum, architecture mismatch, unsafe path handling, or malicious
    local filesystem state.

  Bisq is an open-source project maintained by contributors. Response times may
  vary, but reports involving binary supply-chain compromise, incorrect checksum
  metadata, malicious or wrong-platform Tor binaries, Tor bypass, IP leakage, or
  traffic deanonymization are treated as urgent security issues and will be
  triaged as quickly as possible.

  For lower-severity issues, maintainers will respond when contributor capacity is
  available.

  If the report is accepted, maintainers may coordinate a fix privately, prepare a
  patched branch or binary update, notify the Tor Project when appropriate, and
  publish an advisory after users have had a reasonable opportunity to update. If
  the report is declined, maintainers will explain the reason when possible.

  Please give maintainers reasonable time to investigate and release mitigations
  before public disclosure. For severe or actively exploited issues, coordinate
  timing with maintainers so public details do not increase risk to users.

  Bisq does not currently guarantee a bug bounty. Security work may be eligible
  for Bisq DAO compensation if it qualifies under the project's contributor and
  critical-bug processes.
