#[test_only]
module tokenization::legacy_regulation_bypass;

use share::share;
use tokenization::tokenization;
use tokenization::fixtures;
use sui::coin;
use sui::coin_registry;
use sui::deny_list::{Self, DenyList};
use sui::test_scenario;
use std::unit_test::destroy;

public struct LEGACY_REGULATION_BYPASS has drop {}

#[test, expected_failure(abort_code = 5, location = tokenization)]
#[allow(deprecated_usage)]
fun legacy_unknown_regulation_rejected() {
    let mut scenario = test_scenario::begin(@0x0);
    deny_list::create_for_testing(scenario.ctx());
    scenario.next_tx(@0x0);
    let ctx = scenario.ctx();
    let mut subject = fixtures::subject(ctx);
    let (issuance, mut shares) = share::new(subject.uid(), 100_000_000_000_000, 6);
    // This is the real legacy production coin constructor. In deployment the
    // witness is supplied by init; test construction merely sets up that state.
    let (treasury, mut deny, legacy) = coin::create_regulated_currency_v2(
        LEGACY_REGULATION_BYPASS {}, 6, b"BAD", b"Legacy regulated", b"", option::none(), true, ctx,
    );
    let mut coin_registry = coin_registry::create_coin_data_registry_for_testing(ctx);
    // This helper invokes the exact same migration macro as the public
    // migrate_legacy_metadata API, but returns the Currency for unit testing.
    let mut currency = coin_registry::migrate_legacy_metadata_for_testing(&mut coin_registry, &legacy, ctx);
    currency.set_treasury_cap_id(&treasury);
    let metadata = currency.claim_metadata_cap(&treasury, ctx);
    currency.delete_metadata_cap(metadata);
    assert!(!currency.is_regulated()); // Unknown is reported as false.
    assert!(currency.is_metadata_cap_deleted());

    let mut tokens = tokenization::registry_for_testing(ctx);
    let (mut conversion, initial) = tokenization::initialize(&mut tokens, &issuance, shares.split(1), &currency, treasury);
    destroy(initial);
    let receipt = coin::from_balance(conversion.tokenize(shares.split(100)), ctx);
    assert!(conversion.tokenized_supply() == 101);

    // The regulator remains usable despite the adapter's no-regulation check.
    let mut deny_list = scenario.take_shared<DenyList>();
    coin::deny_list_v2_enable_global_pause(&mut deny_list, &mut deny, scenario.ctx());
    assert!(coin::deny_list_v2_is_global_pause_enabled_next_epoch<LEGACY_REGULATION_BYPASS>(&deny_list));
    coin::deny_list_v2_add(&mut deny_list, &mut deny, @0xB, scenario.ctx());
    assert!(coin::deny_list_v2_contains_next_epoch<LEGACY_REGULATION_BYPASS>(&deny_list, @0xB));
    // Reporting the already-existing cap afterward updates registry metadata.
    currency.migrate_regulated_state_by_cap(&deny);
    assert!(currency.is_regulated());
    tokenization::share(conversion);
    test_scenario::return_shared(deny_list);
    destroy(tokens); destroy(subject); destroy(issuance); destroy(shares);
    destroy(currency); destroy(coin_registry); destroy(legacy); destroy(deny); destroy(receipt);
    scenario.end();
}
