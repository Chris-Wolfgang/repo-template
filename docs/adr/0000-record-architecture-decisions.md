# ADR 0000 — Record architecture decisions

- **Status:** Accepted
- **Date:** 2026-11-20
- **Deciders:** Chris Wolfgang

## Context

A repository collects design choices that the code does not explain on its own: why a type is shaped the way it is,
why an API is missing, why a setting is pinned. Months after the PR that made the choice, the reason is gone. The
commit message is short, the PR discussion is buried, and the next maintainer works the trade-off out again, sometimes
reaching a different answer and undoing the original intent.

## Decision

We will keep short **Architecture Decision Records** in `docs/adr/`, one file per decision that is not obvious from
the code, using [Michael Nygard's format](https://cognitect.com/blog/2011/11/15/documenting-architecture-decisions):
Context, Decision, Alternatives considered, Consequences.

- **This record is 0000.** It describes the practice, so it sits before every decision record and has the same number
  in every repository. Decision records start at 0001.
- **File names are `NNNN-short-slug.md`**: a 4-digit, zero-padded number and a kebab-case title. Copy
  [`TEMPLATE.md`](TEMPLATE.md) and use the next number after the highest one listed in [`index.md`](index.md).
- **Numbers never change and are never reused.** Code comments, XML docs, CHANGELOG entries, issues and commit
  messages cite ADRs by number, and many of those cannot be edited. A number that moved, or went to a new record,
  would make them point at a different decision. A removed record leaves its number retired, with one line in
  `index.md` saying so.
- **An accepted record is not rewritten.** A reversal is a new record. The old record's status becomes
  `Superseded by [NNNN](NNNN-slug.md)`, and the file stays, so links keep working and the history of the reasoning
  survives.
- **A record lands in the same PR as the change it explains**, so it is reviewed with the code.

## Alternatives considered

- **A wiki or an external doc site.** It drifts from the code because it is not versioned with it and is not part of
  the PR review.
- **Long XML doc comments.** Good for how to use an API, poor for why it has its shape. They cannot hold reasoning
  that spans several types or record the options that were rejected.
- **Numbering this record 0001.** Repositories that adopted ADRs after making other decisions would have to renumber
  every record to free 0001, breaking every citation above. 0000 is free everywhere; MADR numbers its own process
  record 0000 the same way.
- **No records.** The reasons keep disappearing; that cost is why this record exists.

## Consequences

- A PR that makes a design decision comes with a record. That is a small, deliberate cost on those PRs.
- `docs/adr/` is the first place to look before changing a decision that other code depends on.
- Records can be written after the fact to capture decisions made before the practice began. They take the next free
  number like any other.
- Gaps in the numbering are expected (retired numbers) and are listed in `index.md`.
