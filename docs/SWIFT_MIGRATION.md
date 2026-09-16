# Swift migration (0.7.0)

The AppKit UI, visibility policy, restriction lifecycle, system discovery, menu activation, and maintenance logic now use Swift. The only production Objective-C is a 47-line header/implementation bridge that checks private selectors and catches Objective-C exceptions. The existing Python iStat helper is unchanged.

The bundle identifier, local signing identity, defaults keys, imported rules, login registration, window geometry, and Accessibility requirements are preserved. Release uses `-O` and whole-module optimization. There is no SwiftUI rewrite or increase in polling frequency. The 60-second maintenance timer, 10-second tolerance, hourly helper audit, icon cache, render cache, bounded AX traversal, and acknowledgement-driven menu activation remain in place. Background cancellation uses a lock to retain the old atomic access semantics.

## Validation

- Debug and Release builds succeeded on macOS 27.0 (26A428).
- Seven existing Python compatibility tests passed unchanged.
- 1,536 deterministic policy scenarios produce the same JSON digest as Objective-C v0.6.8 (`66eabab47f917d16c966edfde720ac5656ff4ecd`): allowlists, hidden-panel contents, and isolated temporary reveals.
- Production Swift tests cover assertion handoff, supersession, stale callbacks, failure, timeout, exact-once release, protected drop rules, AX traversal deduplication/budgets, click bounds across displays, wrapping through 100 items, helper fingerprints/backoff, and live runtime enumeration.
- Native checks confirmed the same settings layout, search, resize/reflow, iStat drag into Hide and back to Always Show, persisted rules after restart, and native Battery/iStat menus. Existing Accessibility permission survived installation. Native drag automation occasionally required a restart, as it did with the prior build; that tool limitation prevents claiming exhaustive drag-event validation.

## Local measurements

These are developer-machine samples, not universal performance guarantees or power measurements.

| Measurement | Objective-C 0.6.8 | Swift 0.7.0 |
| --- | ---: | ---: |
| 10,000 visibility plans, median of five optimized runs | 400.9 ms | 153.5 ms |
| Warm idle CPU time over 65 seconds | 0.07 s | 0.07 s |
| Fresh background launch physical footprint (`sample`) | 13.3 MB | 13.6 MB |
| Battery target ready / action return, one live sample | 216 / 225 ms | 194 / 198 ms |
| Installed executable size | 252,896 bytes | 524,560 bytes |

The policy benchmark uses 100 running app identifiers, 52 rules, and 12 discovered system categories. Checksums match. Run `python3 tests/benchmark.py` to repeat it in a clone containing the baseline commit. The Swift executable is about 265 KiB larger. The small measured memory increase should not be described as zero overhead; idle CPU and sampled interaction latency did not regress.

The unchanged private macOS API still limits compatibility. This migration does not resolve the pre-existing Spotlight activation uncertainty or shared legacy-host limitation. An actual logout/login, sleep/wake cycle, every third-party menu, and physical multi-display operation were not comprehensively retested. Keep the previous release available for rollback.
