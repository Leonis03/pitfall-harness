# os-install -- installing an OS, and the contracts that cross the install boundary

*English · [中文](README.zh.md) · back to [repo README](../README.md)*

Notes for **installing** an operating system, and for the things that only exist
*because* two systems share the same machine.

## Scope rule

| A topic belongs to | Where it goes |
| :--- | :--- |
| One operating system only (a Windows setting, a Linux package) | [`../windows/`](../windows/) or [`../linux-desktop/`](../linux-desktop/) |
| The install itself (partitioning, the bootloader, the first-boot order) | this directory |
| A **contract between the installed systems** -- one value that both sides must agree on | this directory |

The second and third rows are what makes this directory worth its own place. A
contract is invisible from either side: each system looks self-consistent, the
mismatch only shows when you boot the other one, and nothing in the firmware
records the choice. Such a contract has to be written down, or it is rediscovered
as a bug.

## Contents

| File | Contents |
| :--- | :--- |
| [`dual-boot-time-sync.md`](dual-boot-time-sync.md) | **The clock contract between a dual-booted Windows and Linux**: the RTC convention, the 8-hour signature, how to diagnose which side misreads the hardware clock, how to choose between automatic correction and deliberate drift, and the fast-startup interaction |
| [`files/`](files/) | The read-only probe scripts that report the state of both sides |

## Conventions in this directory

- **English first.** `x.md` is the agent-facing baseline, `x.zh.md` the direct
  Chinese translation for human reference.
- **The scripts in `files/` never change anything.** They read state and report
  it. Every fix is a command an operator runs on purpose, and it is written down
  in the prose, next to the measurement that justified it.
- **No real identifiers.** Host names, user names and IP addresses are
  placeholders; see [`../redaction.md`](../redaction.md).
- **ASCII in file names and in every config file**, including comments. LF line
  endings. See [`../conventions.md`](../conventions.md).
