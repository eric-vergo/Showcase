import Verso
import VersoManual
import VersoBlueprint

open Verso.Genre
open Verso.Genre.Manual
open Informal

set_option verso.blueprint.foreignLsp.rust.prelude "/// Return the next value in the Collatz orbit.
pub fn collatz_step(n: u64) -> u64 {
    if n % 2 == 0 {
        n / 2
    } else {
        3 * n + 1
    }
}

/// Count how long the Collatz orbit of `n` takes to reach `1`.
pub fn collatz_total_stopping_time(mut n: u64) -> u64 {
    let mut steps = 0;
    while n > 1 {
        n = collatz_step(n);
        steps += 1;
    }
    steps
}

/// Check the Collatz conjecture by exhaustive search below a finite bound.
pub fn collatz_holds_below(limit: u64) -> bool {
    for n in 1..=limit {
        if collatz_total_stopping_time(n) > 10_000 {
            return false;
        }
    }
    true
}

/// Default finite bound used by the preview search.
pub const COLLATZ_LIMIT: u64 = 10_000;

/// A familiar starting value with a long but finite Collatz orbit.
pub static COLLATZ_START: u64 = 27;

/// A small record for Collatz computations.
pub struct CollatzRecord {
    pub start: u64,
    pub steps: u64,
}

/// The parity branch selected by one Collatz step.
pub enum CollatzParity {
    Even,
    Odd,
}

/// A trait shape included to exercise Rust's type namespace.
pub trait CollatzMeasure {
    fn measure(&self) -> u64;
}

/// A type alias included to exercise Rust's type namespace.
pub type CollatzValue = u64;

pub fn record_for(start: u64) -> CollatzRecord {
    CollatzRecord {
        start,
        steps: collatz_total_stopping_time(start),
    }
}"
set_option verso.blueprint.foreignLsp.timeoutMs 10000

#doc (Manual) "Foreign Rust References" =>

This chapter previews foreign Rust references backed by a live language-server
lookup. Resolved references render a compact Rust source link and a grouped Rust
code panel fetched from the location returned by `rust-analyzer`.

:::definition "rust_case_resolved_function" (rust := "collatz_step")
The Collatz step sends an even number to half of itself and an odd number to
`3n + 1`.
:::

:::definition "rust_case_grouped_functions" (rust := "collatz_total_stopping_time, collatz_holds_below")
The bounded search version measures each orbit and checks a finite prefix of the
Collatz conjecture.
:::

:::definition "rust_case_value_constants" (rust := "COLLATZ_LIMIT, COLLATZ_START")
Constants and statics live in Rust's value namespace, so the current synthetic
lookup strategy resolves them like functions.
:::

:::definition "rust_case_partial_lookup" (rust := "collatz_step, collatz_typo")
A mixed attachment keeps the resolved reference and reports the missing one as a
warning.
:::

:::definition "rust_case_missing_symbol" (rust := "missing_collatz_symbol")
A completely missing Rust symbol produces an unresolved reference without a code
panel.
:::

:::definition "rust_case_type_namespace" (rust := "CollatzRecord, CollatzParity, CollatzMeasure, CollatzValue")
These names exercise Rust's type namespace. They are included as a live preview
of the current synthetic lookup shape, which is still optimized for value
references.
:::
