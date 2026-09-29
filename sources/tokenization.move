// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0

/// Optional, reversible 1:1 conversion. Treasury access never escapes this module.
/// Every outstanding token base unit is backed by one native share unit.
module tokenization::tokenization;

use share::share::{Self, Share};
use sui::balance::Balance;
use sui::coin::{Self, TreasuryCap};
use sui::coin_registry::Currency;
use sui::event;
use sui::derived_object;
use std::type_name::with_defining_ids;

public struct TokenizationKey(ID) has copy, drop, store;

const ENotZeroSupply: u64 = 0;
const EMetadataNotLocked: u64 = 1;
const EInvalidDecimals: u64 = 2;
const ERegulatedCurrency: u64 = 3;
const ETreasuryMismatch: u64 = 4;
const EInvalidShareType: u64 = 5;
const EZeroBacking: u64 = 6;
const SHARE_TYPE: vector<u8> = b"::share::Share";

public struct Tokenization<phantom T> has key {
    id: UID,
    backing: Share,
    treasury: TreasuryCap<T>,
}

public struct TokenizationCreated<phantom T> has copy, drop {
    tokenization_id: ID,
    issuance_id: ID,
    currency_id: ID,
}

/// Anyone holding nonzero shares can establish the canonical tokenization in
/// this registry. The first initializer supplies the immutable currency metadata.
/// The exact currency type name excludes legacy OTW/Unknown regulation paths.
public fun initialize<T>(
    registry: &mut TokenizationRegistry,
    shares: Share,
    currency: &Currency<T>,
    mut treasury: TreasuryCap<T>,
): (Tokenization<T>, Balance<T>) {
    assert!(shares.value() > 0, EZeroBacking);
    assert!(has_share_type_name<T>(), EInvalidShareType);
    assert!(currency.treasury_cap_id() == option::some(object::id(&treasury)), ETreasuryMismatch);
    assert!(coin::total_supply(&treasury) == 0, ENotZeroSupply);
    assert!(currency.is_metadata_cap_deleted(), EMetadataNotLocked);
    assert!(currency.decimals() == share::decimals!(), EInvalidDecimals);
    assert!(!currency.is_regulated(), ERegulatedCurrency);
    let issuance_id = shares.issuance_id();
    let initial_balance = treasury.mint_balance(shares.value());
    let tokenization = Tokenization {
        id: derived_object::claim(&mut registry.id, TokenizationKey(issuance_id)),
        backing: shares,
        treasury,
    };
    event::emit(TokenizationCreated<T> {
        tokenization_id: object::id(&tokenization),
        issuance_id,
        currency_id: object::id(currency),
    });
    (tokenization, initial_balance)
}

/// The only production by-value consumer: initialization must end by sharing.
public fun share<T>(self: Tokenization<T>) { transfer::share_object(self) }

public fun derive_tokenization_id(registry: &TokenizationRegistry, issuance_id: ID): ID {
    derived_object::derive_address(object::id(registry), TokenizationKey(issuance_id)).to_id()
}

public fun issuance_id<T>(self: &Tokenization<T>): ID { self.backing.issuance_id() }
public fun tokenized_supply<T>(self: &Tokenization<T>): u64 {
    coin::total_supply(&self.treasury)
}

public fun tokenize<T>(self: &mut Tokenization<T>, shares: Share): Balance<T> {
    let amount = shares.value();
    self.backing.join(shares);
    self.treasury.mint_balance(amount)
}

public fun detokenize<T>(self: &mut Tokenization<T>, balance: Balance<T>): Share {
    let amount = self.treasury.supply_mut().decrease_supply(balance);
    self.backing.split(amount)
}

/// Preserve the original share currency gate. Legacy constructors require an
/// uppercase OTW name; `share::Share` cannot be one, so Unknown regulation from
/// legacy migration cannot enter this path. Generic instantiations also fail.
fun has_share_type_name<T>(): bool {
    let name = with_defining_ids<T>();
    let bytes = name.as_string().as_bytes();
    let suffix = SHARE_TYPE;
    if (bytes.length() < suffix.length()) return false;
    let offset = bytes.length() - suffix.length();
    let mut i = 0;
    while (i < suffix.length()) {
        if (bytes[offset + i] != suffix[i]) return false;
        i = i + 1;
    };
    true
}

#[test_only]
public fun has_share_type_name_for_testing<T>(): bool { has_share_type_name<T>() }

/// Initialized once per package publication; no production constructor or UID accessor.
public struct TokenizationRegistry has key { id: UID }
public struct RegistryCreated has copy, drop { registry_id: ID }

fun init(ctx: &mut TxContext) {
    let registry = TokenizationRegistry { id: object::new(ctx) };
    event::emit(RegistryCreated { registry_id: object::id(&registry) });
    transfer::share_object(registry);
}

public fun backing_value<T>(self: &Tokenization<T>): u64 { self.backing.value() }

#[test_only]
public fun registry_for_testing(ctx: &mut TxContext): TokenizationRegistry {
    TokenizationRegistry { id: object::new(ctx) }
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) { init(ctx) }
