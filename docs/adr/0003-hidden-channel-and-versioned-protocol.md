# 0003. A hidden permanent channel and a versioned protocol

- Status: Accepted (the channel name waits for the owner's confirmation, [SPEC-10](../specs/SPEC-10-risks-open-questions.md) Q1)
- Date: 2026-11-08 ([SPEC-02](../specs/SPEC-02-network-protocol.md))

## Context

The peer-to-peer catalog ([ADR 0001](0001-client-only-addon-peer-to-peer-catalog.md)) needs a place where every installation can talk. Temporary channels refuse addon messages on Forever, and a channel that was once joined can stay in the game's list even after `/leave`.

## Decision

1. One **permanent** custom channel, `AzGuildFinder`, hidden from every chat window, moved to the end of the channel list, with its join and leave notices filtered.
2. Addon prefix `AzGF`; every message carries `v`, the protocol version. **The channel name never changes after release**: the protocol evolves through `v`.
3. Messages are CBOR, compressed above 120 bytes, Base64-encoded and split by AceComm. Unknown fields are ignored; malformed messages are dropped silently.
4. Traffic is bounded: one channel message every 1.2 s and about 2 KB per minute, suppression when another client already said the same thing, and a queue during chat lockdown or addon restrictions.
5. Bulk answers (catalog and details) go by whisper to whoever asked; guild data by `GUILD`; officer data by `OFFICER`.

## Alternatives considered

- **A temporary channel.** Refused by the servers for addon messages.
- **A new channel name for each protocol version.** Old channels stay behind; rejected.

## Consequences

- Positive: one shared place, forward-compatible messages, bounded traffic.
- Negative: the name is permanent; characters that cannot send in channels fall back to listening only.
