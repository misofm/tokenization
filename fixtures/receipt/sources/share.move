// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0
#[test_only]
module receipt_fixture::share;

use sui::coin::{TreasuryCap, DenyCapV2};
use sui::coin_registry::{Self, Currency, MetadataCap};
use std::unit_test::destroy;

public struct Share has key { id: UID }
public struct OtherShare has key { id: UID }
public fun currency(
    decimals: u8,
    ctx: &mut TxContext,
): (Currency<Share>, TreasuryCap<Share>, MetadataCap<Share>) {
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ctx);
    let (builder, treasury) = coin_registry::new_currency<Share>(
        &mut registry, decimals, b"OWN".to_string(), b"Ownership".to_string(),
        b"".to_string(), b"".to_string(), ctx,
    );
    let (currency, metadata) = coin_registry::finalize_unwrap_for_testing(builder, ctx);
    destroy(registry);
    (currency, treasury, metadata)
}

public fun other_currency(
    ctx: &mut TxContext,
): (Currency<OtherShare>, TreasuryCap<OtherShare>) {
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ctx);
    let (builder, treasury) = coin_registry::new_currency<OtherShare>(
        &mut registry, 6, b"ALT".to_string(), b"Other".to_string(),
        b"".to_string(), b"".to_string(), ctx,
    );
    let (mut currency, metadata) = coin_registry::finalize_unwrap_for_testing(builder, ctx);
    currency.delete_metadata_cap(metadata);
    destroy(registry);
    (currency, treasury)
}

public fun regulated(
    ctx: &mut TxContext,
): (Currency<Share>, TreasuryCap<Share>, DenyCapV2<Share>) {
    let mut registry = coin_registry::create_coin_data_registry_for_testing(ctx);
    let (mut builder, treasury) = coin_registry::new_currency<Share>(
        &mut registry, 6, b"REG".to_string(), b"Regulated".to_string(),
        b"".to_string(), b"".to_string(), ctx,
    );
    let deny = coin_registry::make_regulated(&mut builder, false, ctx);
    let (mut currency, metadata) = coin_registry::finalize_unwrap_for_testing(builder, ctx);
    currency.delete_metadata_cap(metadata);
    destroy(registry);
    (currency, treasury, deny)
}
