// Copyright (c) Miso Labs, Inc.
// SPDX-License-Identifier: Apache-2.0
#[test_only]
module tokenization::tokenization_tests;

use share::share::{Self, Share};
use tokenization::tokenization::{Self, Tokenization, TokenizationRegistry};
use tokenization::fixtures::{Self, Share as WrongModuleShare};
use receipt_fixture::share::Share as Receipt;
use sui::coin;
use sui::test_scenario;
use std::unit_test::destroy;

public struct Wallet has key, store { id: UID, shares: Share }

#[test]
fun holder_initializes_without_subject_authority_and_another_holder_redeems() {
    let mut scenario = test_scenario::begin(@0x0);
    tokenization::init_for_testing(scenario.ctx());
    let mut registry = share::registry_for_testing(scenario.ctx());
    let mut subject = fixtures::subject(scenario.ctx());
    let (issuance, mut shares) = share::initialize_for_testing(&mut registry, subject.uid());
    let issuance_id = object::id(&issuance);
    let gift = shares.split(1_500);
    let (mut currency, treasury, metadata) = fixtures::currency(share::decimals!(), scenario.ctx());
    currency.delete_metadata_cap(metadata);
    // Currency can be read by any holder; treasury is handed to B for binding.
    // Test-only disposal of its object wrapper does not affect validation below.
    transfer::public_transfer(treasury, @0xB);
    transfer::public_transfer(Wallet { id: object::new(scenario.ctx()), shares: gift }, @0xB);
    subject.keep(@0x0);
    destroy(registry); destroy(issuance);
    scenario.next_tx(@0xB);
    let mut tokens = scenario.take_shared<TokenizationRegistry>();
    let expected = tokenization::derive_tokenization_id(&tokens, issuance_id);
    let Wallet { id, shares: gift } = scenario.take_from_sender<Wallet>();
    id.delete();
    let treasury = scenario.take_from_sender<coin::TreasuryCap<Receipt>>();
    let (mut conversion, balance) = tokenization::initialize(&mut tokens, gift, &currency, treasury);
    assert!(object::id(&conversion) == expected);
    assert!(conversion.issuance_id() == issuance_id);
    assert!(conversion.backing_value() == conversion.tokenized_supply());
    let mut receipt = coin::from_balance(balance, scenario.ctx());
    let gift_coin = receipt.split(500, scenario.ctx());
    // Return B's remaining tokens to native ownership before sending C theirs.
    let returned = conversion.detokenize(receipt.into_balance());
    shares.join(returned);
    assert!(shares.value() + conversion.backing_value() == share::max_supply!());
    transfer::public_transfer(gift_coin, @0xC);
    tokenization::share(conversion);
    test_scenario::return_shared(tokens);
    destroy(currency);
    scenario.next_tx(@0xC);
    let mut conversion = scenario.take_shared<Tokenization<Receipt>>();
    let receipt = scenario.take_from_sender<coin::Coin<Receipt>>();
    let returned = conversion.detokenize(receipt.into_balance());
    assert!(returned.value() == 500);
    shares.join(returned);
    assert!(shares.value() == share::max_supply!());
    assert!(conversion.tokenized_supply() == 0);
    assert!(conversion.backing_value() == 0);
    test_scenario::return_shared(conversion);
    destroy(shares);
    scenario.end();
}

#[test]
fun repeated_partial_and_full_roundtrips_preserve_backing() {
    let ctx = &mut tx_context::dummy();
    let mut registry = share::registry_for_testing(ctx);
    let mut subject = fixtures::subject(ctx);
    let (issuance, mut shares) = share::initialize_for_testing(&mut registry, subject.uid());
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(share::decimals!(), ctx);
    currency.delete_metadata_cap(metadata);
    let (mut conversion, mut coins) = tokenization::initialize(&mut tokens, shares.split(1), &currency, treasury);
    let mut i = 0;
    while (i < 100) {
        coins.join(conversion.tokenize(shares.split(i * 37)));
        shares.join(conversion.detokenize(coins.split(i * 13)));
        assert!(conversion.tokenized_supply() == conversion.backing_value());
        assert!(shares.value() + conversion.backing_value() == share::max_supply!());
        i = i + 1;
    };
    shares.join(conversion.detokenize(coins));
    let all = conversion.tokenize(shares.withdraw_all());
    shares.destroy_zero();
    assert!(all.value() == share::max_supply!());
    assert!(conversion.backing_value() == share::max_supply!());
    let all = conversion.detokenize(all);
    assert!(all.value() == share::max_supply!());
    assert!(conversion.tokenized_supply() == 0);
    assert!(conversion.backing_value() == 0);
    let zero = conversion.tokenize(share::zero(&issuance));
    conversion.detokenize(zero).destroy_zero();
    destroy(all); destroy(conversion); destroy(currency); destroy(tokens);
    destroy(issuance); destroy(registry); destroy(subject);
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
    let mut registry = share::registry_for_testing(ctx);
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::initialize_for_testing(&mut registry, subject.uid());
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, mut treasury, metadata) = fixtures::currency(share::decimals!(), ctx);
    currency.delete_metadata_cap(metadata);
    let preexisting = treasury.mint_balance(1);
    let (conversion, balance) = tokenization::initialize(&mut tokens, shares, &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(registry); destroy(subject); destroy(preexisting);
}

#[test, expected_failure(abort_code = 1, location = tokenization)]
fun mutable_metadata_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = share::registry_for_testing(ctx);
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::initialize_for_testing(&mut registry, subject.uid());
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (currency, treasury, metadata) = fixtures::currency(share::decimals!(), ctx);
    let (conversion, balance) = tokenization::initialize(&mut tokens, shares, &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(registry); destroy(subject); destroy(metadata);
}

#[test, expected_failure(abort_code = 2, location = tokenization)]
fun wrong_decimals_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = share::registry_for_testing(ctx);
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::initialize_for_testing(&mut registry, subject.uid());
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(9, ctx);
    currency.delete_metadata_cap(metadata);
    let (conversion, balance) = tokenization::initialize(&mut tokens, shares, &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(registry); destroy(subject);
}

#[test, expected_failure(abort_code = 3, location = tokenization)]
fun regulated_currency_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = share::registry_for_testing(ctx);
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::initialize_for_testing(&mut registry, subject.uid());
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (currency, treasury, deny) = fixtures::regulated(ctx);
    let (conversion, balance) = tokenization::initialize(&mut tokens, shares, &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(registry); destroy(subject); destroy(deny);
}

#[test, expected_failure(abort_code = 4, location = tokenization)]
fun noncanonical_treasury_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = share::registry_for_testing(ctx);
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::initialize_for_testing(&mut registry, subject.uid());
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(share::decimals!(), ctx);
    currency.delete_metadata_cap(metadata);
    let fake = coin::create_treasury_cap_for_testing<Receipt>(ctx);
    let (conversion, balance) = tokenization::initialize(&mut tokens, shares, &currency, fake);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(registry); destroy(subject); destroy(treasury);
}

#[test, expected_failure(abort_code = 5, location = tokenization)]
fun wrong_token_name_rejected() {
    let ctx = &mut tx_context::dummy();
    let mut registry = share::registry_for_testing(ctx);
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::initialize_for_testing(&mut registry, subject.uid());
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (currency, treasury) = fixtures::other_currency(ctx);
    let (conversion, balance) = tokenization::initialize(&mut tokens, shares, &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(registry); destroy(subject);
}

#[test, expected_failure(abort_code = 6, location = tokenization)]
fun zero_holder_cannot_claim_tokenization() {
    let ctx = &mut tx_context::dummy();
    let mut registry = share::registry_for_testing(ctx);
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::initialize_for_testing(&mut registry, subject.uid());
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(share::decimals!(), ctx);
    currency.delete_metadata_cap(metadata);
    let (conversion, balance) = tokenization::initialize(&mut tokens, share::zero(&issuance), &currency, treasury);
    destroy(conversion); destroy(balance); destroy(tokens); destroy(currency); destroy(issuance);
    destroy(registry); destroy(subject); destroy(shares);
}

#[test, expected_failure(abort_code = sui::derived_object::EObjectAlreadyExists)]
fun duplicate_tokenization_rejected_even_after_emptying_backing() {
    let ctx = &mut tx_context::dummy();
    let mut registry = share::registry_for_testing(ctx);
    let mut subject = fixtures::subject(ctx);
    let (issuance, mut shares) = share::initialize_for_testing(&mut registry, subject.uid());
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(share::decimals!(), ctx);
    currency.delete_metadata_cap(metadata);
    let (mut first, balance) = tokenization::initialize(&mut tokens, shares.split(1), &currency, treasury);
    shares.join(first.detokenize(balance));
    assert!(first.backing_value() == 0);
    let (mut other_currency, other_treasury, metadata) = fixtures::currency(share::decimals!(), ctx);
    other_currency.delete_metadata_cap(metadata);
    let (second, balance) = tokenization::initialize(&mut tokens, shares, &other_currency, other_treasury);
    destroy(first); destroy(second); destroy(balance); destroy(currency); destroy(other_currency);
    destroy(tokens); destroy(issuance); destroy(registry); destroy(subject);
}

#[test, expected_failure(abort_code = 1, location = share)]
fun foreign_issuance_cannot_tokenize() {
    let ctx = &mut tx_context::dummy();
    let mut registry = share::registry_for_testing(ctx);
    let mut subject = fixtures::subject(ctx);
    let (issuance, shares) = share::initialize_for_testing(&mut registry, subject.uid());
    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut currency, treasury, metadata) = fixtures::currency(share::decimals!(), ctx);
    currency.delete_metadata_cap(metadata);
    let (mut conversion, balance) = tokenization::initialize(&mut tokens, shares, &currency, treasury);
    let mut foreign = fixtures::subject(ctx);
    let (foreign_issuance, foreign_shares) = share::initialize_for_testing(&mut registry, foreign.uid());
    let invalid = conversion.tokenize(foreign_shares);
    destroy(invalid); destroy(balance); destroy(conversion); destroy(currency); destroy(tokens);
    destroy(foreign); destroy(foreign_issuance);
    destroy(issuance); destroy(registry); destroy(subject);
}
