// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0
#[test_only]
module tokenization::tokenization_tests;

use share::share::{Self, Issuance, Share};
use tokenization::tokenization::{Self, Tokenization, TokenizationRegistry};
use tokenization::fixtures::{Self, Share as WrongModuleShare};
use receipt_fixture::share::Share as Receipt;
use sui::coin;
use sui::test_scenario;
use std::unit_test::destroy;

const SUPPLY: u64 = 100_000_000_000_000;
const DECIMALS: u8 = 6;

public struct Wallet has key, store { id: UID, shares: Share }

#[test]
fun holder_initializes_without_parent_authority_and_another_holder_redeems() {
    let mut scenario = test_scenario::begin(@0x0);
    tokenization::init_for_testing(scenario.ctx());
    scenario.next_tx(@0x0);
    let mut subject = fixtures::subject(scenario.ctx());
    let (new_issuance, mut shares) = share::new(subject.uid(), SUPPLY, DECIMALS);
    new_issuance.share();
    let issuance_id = shares.issuance_id();
    let gift = shares.split(1_500);
    let (mut currency, treasury, metadata) = fixtures::currency(DECIMALS, scenario.ctx());
    currency.delete_metadata_cap(metadata);
    // Currency can be read by any holder; treasury is handed to B for binding.
    transfer::public_transfer(treasury, @0xB);
    transfer::public_transfer(Wallet { id: object::new(scenario.ctx()), shares: gift }, @0xB);
    subject.keep(@0x0);
    scenario.next_tx(@0xB);
    let issuance = scenario.take_shared<Issuance>();
    let mut tokens = scenario.take_shared<TokenizationRegistry>();
    let expected = tokenization::derive_tokenization_id(&tokens, issuance_id);
    let Wallet { id, shares: gift } = scenario.take_from_sender<Wallet>();
    id.delete();
    let treasury = scenario.take_from_sender<coin::TreasuryCap<Receipt>>();
    let (mut conversion, balance) = tokenization::initialize(&mut tokens, &issuance, gift, &currency, treasury);
    assert!(object::id(&conversion) == expected);
    assert!(conversion.issuance_id() == issuance_id);
    assert!(conversion.backing_value() == conversion.tokenized_supply());
    let mut receipt = coin::from_balance(balance, scenario.ctx());
    let gift_coin = receipt.split(500, scenario.ctx());
    // Return B's remaining tokens to native ownership before sending C theirs.
    let returned = conversion.detokenize(receipt.into_balance());
    shares.join(returned);
    assert!(shares.value() + conversion.backing_value() == SUPPLY);
    transfer::public_transfer(gift_coin, @0xC);
    tokenization::share(conversion);
    test_scenario::return_shared(tokens);
    destroy(currency);
    test_scenario::return_shared(issuance);
    scenario.next_tx(@0xC);
    let mut conversion = scenario.take_shared<Tokenization<Receipt>>();
    let receipt = scenario.take_from_sender<coin::Coin<Receipt>>();
    let returned = conversion.detokenize(receipt.into_balance());
    assert!(returned.value() == 500);
    shares.join(returned);
    assert!(shares.value() == SUPPLY);
    assert!(conversion.tokenized_supply() == 0);
    assert!(conversion.backing_value() == 0);
    test_scenario::return_shared(conversion);
    destroy(shares);
    scenario.end();
}

#[test]
fun repeated_partial_and_full_roundtrips_preserve_backing() {
    let ctx = &mut tx_context::dummy();
    let mut subject = fixtures::subject(ctx);
    let (issuance, mut shares) = share::new(subject.uid(), 100_000_000_000_000, 6);
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(DECIMALS, ctx);
    currency.delete_metadata_cap(metadata);
    let (mut conversion, mut coins) = tokenization::initialize(&mut tokens, &issuance, shares.split(1), &currency, treasury);
    let mut i = 0;
    while (i < 100) {
        coins.join(conversion.tokenize(shares.split(i * 37)));
        shares.join(conversion.detokenize(coins.split(i * 13)));
        assert!(conversion.tokenized_supply() == conversion.backing_value());
        assert!(shares.value() + conversion.backing_value() == SUPPLY);
        i = i + 1;
    };
    shares.join(conversion.detokenize(coins));
    let all = conversion.tokenize(shares.withdraw_all());
    shares.destroy_zero();
    assert!(all.value() == SUPPLY);
    assert!(conversion.backing_value() == SUPPLY);
    let all = conversion.detokenize(all);
    assert!(all.value() == SUPPLY);
    assert!(conversion.tokenized_supply() == 0);
    assert!(conversion.backing_value() == 0);
    let zero = conversion.tokenize(share::zero(&issuance));
    conversion.detokenize(zero).destroy_zero();
    destroy(all); destroy(conversion); destroy(currency); destroy(tokens);
    destroy(issuance); destroy(subject);
}

#[test]
fun exact_type_name_gate() {
    assert!(tokenization::has_share_type_name_for_testing<Receipt>());
    assert!(!tokenization::has_share_type_name_for_testing<u64>());
    assert!(!tokenization::has_share_type_name_for_testing<vector<Receipt>>());
    assert!(!tokenization::has_share_type_name_for_testing<receipt_fixture::share::OtherShare>());
    assert!(!tokenization::has_share_type_name_for_testing<WrongModuleShare>());
}

#[test, expected_failure(abort_code = 0, location = tokenization)]
fun nonzero_currency_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::new(subject.uid(), 100_000_000_000_000, 6);
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, mut treasury, metadata) = fixtures::currency(DECIMALS, ctx);
    currency.delete_metadata_cap(metadata);
    let preexisting = treasury.mint_balance(1);
    let (conversion, balance) = tokenization::initialize(&mut tokens, &issuance, shares, &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(subject); destroy(preexisting);
}

#[test, expected_failure(abort_code = 1, location = tokenization)]
fun mutable_metadata_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::new(subject.uid(), 100_000_000_000_000, 6);
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (currency, treasury, metadata) = fixtures::currency(DECIMALS, ctx);
    let (conversion, balance) = tokenization::initialize(&mut tokens, &issuance, shares, &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(subject); destroy(metadata);
}

#[test, expected_failure(abort_code = 2, location = tokenization)]
fun wrong_decimals_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::new(subject.uid(), 100_000_000_000_000, 6);
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(9, ctx);
    currency.delete_metadata_cap(metadata);
    let (conversion, balance) = tokenization::initialize(&mut tokens, &issuance, shares, &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(subject);
}

#[test, expected_failure(abort_code = 3, location = tokenization)]
fun regulated_currency_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::new(subject.uid(), 100_000_000_000_000, 6);
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (currency, treasury, deny) = fixtures::regulated(ctx);
    let (conversion, balance) = tokenization::initialize(&mut tokens, &issuance, shares, &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(subject); destroy(deny);
}

#[test, expected_failure(abort_code = 4, location = tokenization)]
fun noncanonical_treasury_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::new(subject.uid(), 100_000_000_000_000, 6);
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(DECIMALS, ctx);
    currency.delete_metadata_cap(metadata);
    let fake = coin::create_treasury_cap_for_testing<Receipt>(ctx);
    let (conversion, balance) = tokenization::initialize(&mut tokens, &issuance, shares, &currency, fake);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(subject); destroy(treasury);
}

#[test, expected_failure(abort_code = 5, location = tokenization)]
fun wrong_token_name_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::new(subject.uid(), 100_000_000_000_000, 6);
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (currency, treasury) = fixtures::other_currency(ctx);
    let (conversion, balance) = tokenization::initialize(&mut tokens, &issuance, shares, &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(subject);
}

#[test, expected_failure(abort_code = 6, location = tokenization)]
fun zero_holder_cannot_claim_tokenization() {
    let ctx = &mut tx_context::dummy();
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::new(subject.uid(), 100_000_000_000_000, 6);
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(DECIMALS, ctx);
    currency.delete_metadata_cap(metadata);
    let (conversion, balance) = tokenization::initialize(&mut tokens, &issuance, share::zero(&issuance), &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(subject); destroy(shares);
}

#[test, expected_failure(abort_code = sui::derived_object::EObjectAlreadyExists)]
fun duplicate_tokenization_rejected_even_after_emptying_backing() {
    let ctx = &mut tx_context::dummy();
    let mut subject = fixtures::subject(ctx);
    let (issuance, mut shares) = share::new(subject.uid(), 100_000_000_000_000, 6);
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(DECIMALS, ctx);
    currency.delete_metadata_cap(metadata);
    let (mut first, balance) = tokenization::initialize(&mut tokens, &issuance, shares.split(1), &currency, treasury);
    shares.join(first.detokenize(balance));
    assert!(first.backing_value() == 0);
    let (mut other_currency, other_treasury, metadata) = fixtures::currency(DECIMALS, ctx);
    other_currency.delete_metadata_cap(metadata);
    let (second, balance) = tokenization::initialize(&mut tokens, &issuance, shares, &other_currency, other_treasury);
    destroy(first); destroy(second); destroy(balance); destroy(currency); destroy(other_currency);
    destroy(tokens); destroy(issuance); destroy(subject);
}

#[test, expected_failure(abort_code = 1, location = share)]
fun foreign_issuance_cannot_tokenize() {
    let ctx = &mut tx_context::dummy();
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::new(subject.uid(), 100_000_000_000_000, 6);
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(DECIMALS, ctx);
    currency.delete_metadata_cap(metadata);
    let (mut conversion, balance) = tokenization::initialize(&mut tokens, &issuance, shares, &currency, treasury);
    let mut foreign = fixtures::subject(ctx);
    let (foreign_issuance, foreign_shares) = share::new(foreign.uid(), 100_000_000_000_000, 6);
    let invalid = conversion.tokenize(foreign_shares);
    destroy(invalid); destroy(balance); destroy(conversion); destroy(currency); destroy(tokens);
    destroy(foreign); destroy(foreign_issuance);
    destroy(issuance); destroy(subject);
}

#[test]
fun full_u64_supply_and_decimal_range_roundtrip() {
    let ctx = &mut tx_context::dummy();
    configurable_roundtrip(1, 0, ctx);
    configurable_roundtrip(57, 8, ctx);
    configurable_roundtrip(100_000_000_000_000, 6, ctx);
    configurable_roundtrip(std::u64::max_value!(), 255, ctx);
}

fun configurable_roundtrip(supply: u64, decimals: u8, ctx: &mut TxContext) {
    let mut subject = fixtures::subject(ctx);
    let (issuance, mut shares) = share::new(subject.uid(), supply, decimals);
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(decimals, ctx);
    currency.delete_metadata_cap(metadata);
    let (mut conversion, mut balance) = tokenization::initialize(
        &mut tokens, &issuance, shares.split(1), &currency, treasury,
    );
    assert!(balance.value() == 1);
    assert!(conversion.tokenized_supply() == 1);
    assert!(conversion.backing_value() == 1);
    assert!(shares.value() == supply - 1);
    balance.join(conversion.tokenize(shares.withdraw_all()));
    shares.destroy_zero();
    assert!(balance.value() == issuance.supply());
    assert!(conversion.tokenized_supply() == issuance.supply());
    assert!(conversion.backing_value() == issuance.supply());
    let mut returned = conversion.detokenize(balance.split(1));
    assert!(returned.value() == 1);
    assert!(conversion.backing_value() == supply - 1);
    assert!(conversion.tokenized_supply() == supply - 1);
    returned.join(conversion.detokenize(balance));
    assert!(returned.value() == supply);
    assert!(conversion.backing_value() == 0);
    assert!(conversion.tokenized_supply() == 0);
    let all = conversion.tokenize(returned);
    assert!(all.value() == supply);
    let all = conversion.detokenize(all);
    destroy(all); destroy(conversion); destroy(currency); destroy(tokens);
    destroy(issuance); destroy(subject);
}

#[test, expected_failure(abort_code = 7, location = tokenization)]
fun foreign_issuance_cannot_select_currency_parameters() {
    let ctx = &mut tx_context::dummy();
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::new(subject.uid(), 500, 6);
    let mut foreign = fixtures::subject(ctx);
    let (foreign_issuance, foreign_shares) = share::new(foreign.uid(), 1_000, 9);
    let mut tokens = tokenization::registry_for_testing(ctx);
    // These decimals match the foreign issuance, not the backing shares.
    let (mut currency, treasury, metadata) = fixtures::currency(9, ctx);
    currency.delete_metadata_cap(metadata);
    let (conversion, balance) = tokenization::initialize(
        &mut tokens, &foreign_issuance, shares, &currency, treasury,
    );
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency);
    destroy(issuance); destroy(foreign_issuance); destroy(foreign_shares);
    destroy(subject); destroy(foreign);
}
