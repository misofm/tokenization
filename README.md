# Share tokenization

An independently publishable Move package that depends on
[`misofm/share`](https://github.com/misofm/share), pinned to an exact commit.
Subject protocols need only the ownership package; there is no reverse dependency.

## Holder-initiated creation

```move
let (conversion, balance) = tokenization::initialize(
    &mut registry,
    shares,
    &currency,
    treasury_cap,
);
tokenization::share(conversion);
```

Any holder of nonzero shares can create the tokenization. No subject UID, subject
admin capability, or mutable issuance reference is required. The supplied shares
become backing, and the returned balance contains an equal number of coin base
units. Zero ownership cannot reserve a registry entry.

The canonical shared `TokenizationRegistry` is created once at package
initialization. `TokenizationKey(issuance_id)` derives the conversion object's
address under that registry. The permanent claim prevents a second binding,
including after all tokens have been redeemed. Each issuance is independent.

The first holder chooses the currency, subject to the enforced parameters below.
Name, symbol, description and artwork may vary; metadata must be locked before
registration. Canonicality is scoped to this registry, not a prohibition against
other independently published adapters.

## Currency enforcement

Initialization preserves the original share-currency checks:

- Type name is exactly `<address>::share::Share`, with no type parameters.
- The treasury is the canonical treasury recorded on the currency.
- Initial token supply is zero.
- The metadata capability has been deleted.
- Decimals equal the ownership package's public `share::decimals!()` macro.
- Currency is unregulated.

The exact type-name gate excludes legacy OTW currencies. Their migrated registry
status can be Unknown even when a live deny capability exists, so the regulation
flag alone is insufficient. The legacy bypass is covered by a rejection test.

The treasury remains private and live for receipt minting/burning. It cannot be
extracted, replaced or used for arbitrary minting. Publish the package immutably
to preserve those guarantees.

## Conversion and accounting

```move
let balance = conversion.tokenize(shares);
let shares = conversion.detokenize(balance);
```

Tokenization deposits shares by joining them into backing before minting equal
coin units. Redemption burns coin units before splitting shares from backing.
Wrong-issuance deposits abort, including zero-valued deposits. Native shares are
never destroyed and reconstructed across the package boundary.

```text
outstanding token base units = native share units held as backing
backing <= share::max_supply!()
```

The maximum follows from the native package's conserved supply; the adapter has
no independent supply constant or native mint authority. Receipt units represent
backing rather than adding more ownership. Native shares held outside backing
plus the backing always equal the native issuance's fixed supply.

Use Sui's existing `Coin` / `Balance` conversion functions for object coins.
Revenue claims, reward debt and distribution are separate integration concerns.

## API

| Function | Result |
|---|---|
| `initialize(&mut TokenizationRegistry, Share, &Currency<T>, TreasuryCap<T>)` | `(Tokenization<T>, Balance<T>)` |
| `share(Tokenization<T>)` | Shares the conversion object; only by-value consumer |
| `derive_tokenization_id(&TokenizationRegistry, issuance_id)` | Predicted `ID`, not existence proof |
| `issuance_id(&Tokenization<T>)` | Backing issuance ID |
| `backing_value(&Tokenization<T>)` | Native units in custody |
| `tokenized_supply(&Tokenization<T>)` | Outstanding receipt units |
| `tokenize(&mut Tokenization<T>, Share)` | Matching `Balance<T>` |
| `detokenize(&mut Tokenization<T>, Balance<T>)` | Matching native `Share` |

The conversion object is independently shared. Only creation touches the
registry; conversion does not require the issuance or subject. Initialization
must complete by sharing the object in the same transaction.

## Validation

```sh
sui move build
sui move test
```

Tests cover holder-authorized creation without subject authority, deterministic
registry derivation, duplicate and zero-backed creation rejection, cross-issuance
deposits, all currency gates, the legacy regulation regression, and repeated
partial/full conversions preserving exact backing.

Licensed under Apache-2.0.
