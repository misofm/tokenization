// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0
#[test_only]
module tokenization::fixtures;

use sui::coin::{TreasuryCap, DenyCapV2};
use sui::coin_registry::{Currency, MetadataCap};
use receipt_fixture::share::{Self as receipt, Share as Receipt, OtherShare};

/// Deliberately wrong module name for the token type-name guard.
public struct Share has key { id: UID }

public struct Subject has key { id: UID }

public fun subject(ctx: &mut TxContext): Subject { Subject { id: object::new(ctx) } }
public fun uid(self: &mut Subject): &mut UID { &mut self.id }
public fun keep(self: Subject, owner: address) { transfer::transfer(self, owner) }

public fun currency(decimals: u8, ctx: &mut TxContext): (Currency<Receipt>, TreasuryCap<Receipt>, MetadataCap<Receipt>) {
    receipt::currency(decimals, ctx)
}

public fun other_currency(ctx: &mut TxContext): (Currency<OtherShare>, TreasuryCap<OtherShare>) {
    receipt::other_currency(ctx)
}

public fun regulated(ctx: &mut TxContext): (Currency<Receipt>, TreasuryCap<Receipt>, DenyCapV2<Receipt>) {
    receipt::regulated(ctx)
}
