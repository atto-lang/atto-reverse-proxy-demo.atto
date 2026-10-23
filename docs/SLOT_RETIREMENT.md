# Actor-owned slot retirement: safety-first reference

**Status:** pure Oreslang transition system, not a real preallocated arena, GC-free transport or verified network loop. `slot_lifecycle.ores` gives the intended semantics; transitions intentionally copy small arrays of pin serials and allocate new snapshot objects. This representation is too expensive for packet/request hot paths, but can serve as a specification oracle for a future SoA/AoSoA slab.

## Lifecycle invariants

Each physical slot carries independent **incarnation** and **configuration epoch**. `reserve` can only move FREE → OPEN and increments incarnation without wrap. `pin` issues a unique claim serial while OPEN, capped at 64, representing outstanding socket buffers, requests, middleware reads, native I/O or callbacks. `close`/cancel moves OPEN → RETIRING while any pin remains, preventing reuse, and repeated close is idempotent. Each claim must be settled *exactly once* by its serial; a duplicate/forged/late completion is rejected without changing the remaining pins. Only RETIRING + zero pending claims transitions to FREE. A stale ticket/claim cannot affect another incarnation or epoch. `quiescent()` models the join boundary before a parent `get_done()` can acknowledge physical cleanup.

The currently committed SoA `data_layout.ores` remains append-only; it is **not** yet wired to this ledger. Native actor-owned production storage must preallocate typed primitive columns with bounded free-list + incarnation, use atomic/owner-serialized publish/retire, store the pending-pin ledger in bounded slab memory rather than heap arrays, track memory/bytes quotas, and join async I/O retirement before freeing a slot/arena. Any request-ID to slot-ID mapping must be generation checked at every boundary.

## Required negative race scenarios

- Cancel before pending I/O delivery; completion arrives afterward; no leaked or double-freed buffer.
- Cancel in the middle of the grant/dequeue/handoff; parent `get_done()` waits for reclamation.
- Repeated cancellation; duplicate completion; out-of-order different completion receipts.
- New request opens on recycled physical slot with different epoch and cannot see the old request's state.
- Serial/incarnation exhaustion fails closed; memory limits and backpressure protect against pressure from retired-but-pinned entries.
- Concurrent actor and supervisor actors must transfer immutable handles, not mutable slab pointers.
- Streaming tunnel half-close, middleware generation drain, TLS and DNS pinning must retain outstanding capabilities to completion.

## Evidence and next gate

`tests/slot_lifecycle_contract.ores` covers deterministic transition ordering; it is not an adversarial concurrent wire test and does not prove native kernel behavior. Compile and run the exact PR head using the Java/Graal JDK25 compiler and the LLVM compiler, then link the identical transition semantics into the transport's actor-owned SoA/AoSoA slab. The root CLI still uses exclusively `ores_proxy_conf_yaml` with flags-2-env and continues to fail closed without real transport.

No new non-Oreslang application sources or scripts are included.
