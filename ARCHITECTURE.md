# Architecture

How Kotonoha is layered, where each kind of code belongs, and how dependencies
are supplied. It follows the [Flutter architecture guide][guide] and
[recommendations][rec]; the sections below record where Kotonoha follows them,
and where it deliberately does not and why.

The source conventions in [Guards](#guards) are checked by
[`test/architecture/pure_layer_imports_test.dart`](test/architecture/pure_layer_imports_test.dart).
That test walks the listed imports and naming; it does not cover ViewModel
lifecycle, repository snapshot identity, or immutability. Those have their
own tests, and those tests have their own scope. If you change a listed
convention, change its guard in the same commit.

[guide]: https://docs.flutter.dev/app-architecture/guide
[rec]: https://docs.flutter.dev/app-architecture/recommendations
[case-study]: https://docs.flutter.dev/app-architecture/case-study

## Layers

`domain` holds two kinds of code: use cases, and the shared models and
datasets. The data layer is allowed to import the latter —
`KanaProgressRepository` imports `Kana`, `KanaStat`, and the kana /
confusable datasets — so a single arrow **UI → domain → data** would call
those imports a violation.

The actual edges:

- **UI → repositories and services, or use cases when coordination is
  needed.** Views and ViewModels inject repositories and services directly
  (for example `ProgressViewModel`, `StudyViewModel`, and `HomeViewModel`).
  A use case sits between them only when learning rules or coordination spans
  more than one owner. UI also reads the shared models and datasets and does
  not import Flutter platform plugins directly.
- **Use cases** depend on repositories, services, and the shared models and
  datasets. They do not import UI.
- **Repositories and services** depend on each other one way (repositories
  import services; services do not import repositories) and on the shared
  models and datasets. They do not import use cases or UI. A repository does
  not import another repository.
- **Models and datasets** (`lib/domain/models/`, `lib/domain/data/`, and the
  `lib/kanji/domain` equivalents) are shared values. They import neither UI
  nor data.

| Layer | Directory | Owns |
| --- | --- | --- |
| View | `lib/ui/<feature>/<feature>_screen.dart` | Layout, animation, focus, navigation, and forwarding Flutter lifecycle events |
| ViewModel | `lib/ui/<feature>/<feature>_viewmodel.dart` | One feature's UI state and commands |
| Use case | `lib/domain/use_cases/` | Learning rules, and coordination that spans more than one repository |
| Model | `lib/domain/models/` | Immutable values |
| Dataset | `lib/domain/data/` | The fixed teaching content |
| Repository | `lib/data/repositories/` | The single truth owner for one kind of data |
| Service | `lib/data/services/` | One platform source: preferences, files, text to speech |

`lib/kanji/` mirrors the same split for the kanji feature (`kanji/domain`,
`kanji/data`, `kanji/ui`). Grouping one feature this way is allowed by the
official [package structure][case-study] guidance and is not a defect.

Shared UI that belongs to no single feature lives in `lib/ui/core/`: strings,
theme, reusable widgets, and the two app-scoped persistence controllers.

### View

A View renders and routes. It may hold the things Flutter itself owns: a
`PageController`, a `TextEditingController`, an `AppLifecycleListener`, the
speech handle for playback it started, scroll position, and `Navigator` calls.

A View must not decide whether an answer counts, filter learning material, or
write progress. Not every widget needs a ViewModel; a pure display widget takes
values and callbacks.

### ViewModel

One `ChangeNotifier` per feature that has state or commands. Dependencies are
injected through the constructor — usually repositories and services; a use case
only when the feature needs cross-owner coordination. A ViewModel must not
touch `BuildContext`,
`Navigator`, a concrete widget, a platform plugin, or a `Timer`. Presentation
types stay in the UI layer.

The lifecycle contract is the part that has broken most often, so it is stated
explicitly. After an `await`, a command must confirm it still owns what it is
about to change:

- A disposed ViewModel must not call `notifyListeners`.
- A disposed ViewModel must not clear a draft that a later screen has since
  written, advance a session, or record an exposure for something the learner
  never saw.
- Persistence that was already handed to `ProgressPersistenceController` stays
  that controller's to track and retry. Leaving a route cancels the view's work,
  never a write already in flight.

Each of those needs a test that delays a read or write, leaves the route, and
then releases it. Pumping a widget is not required to test a ViewModel; inject
the clock and the random source instead.

### Repository

Each kind of data has exactly one truth owner. A repository owns loading,
caching, retry, durability, and notification for its own data, and nothing else.

What a repository hands out is a snapshot the caller cannot write through.
[`test/repository_ownership_test.dart`](test/repository_ownership_test.dart)
checks the collections it names:

- Kana stats, learned units, seen unlocks, word stats, the travel plan, and
  the placement draft reject mutation, and a snapshot taken before a write
  does not change when the owner writes again.
- Kanji stats is checked only as a cold map: mutation is rejected, but there
  is no owner write in that test.
- `gojuonKana` is a fresh list on each read. The list itself is mutable; the
  test only asserts two reads are not the same object, so a caller writing
  the list cannot reach the owner.

Coordination across two owners is a use case, never a repository reaching for a
sibling. `ProgressSnapshotCapture` and `ProgressRestoreTransaction` are the
examples.

`KanaStat`, `WordStat` and `ReadingStat` mean different things and stay
separate. Do not merge them into one scheduler to make the layering look neater.

### Service

A service wraps one platform source and knows nothing above it. Services do not
import repositories. "A service holds no app state" does not mean a service may
drop cancellation or resource management: the speech service still owns its
playback handle and still has to stop.

## Composition root

`bootstrap()` in [`lib/main.dart`](lib/main.dart) is the only place app-scoped
dependencies are created. It loads every repository, opens the analytics log and
the speech service, wires the two persistence controllers, and provides all of
them above the app.

Eleven objects are registered there today: the three progress repositories
(kana, kanji, word) plus placement and travel — five repositories — then the
persistence and restore-recovery controllers, the speech service, the
analytics log, and the snapshot exporter and restorer.

Two rules follow:

1. **A feature builds and disposes its own ViewModel.** Read the owners it needs
   from the providers in `initState`, construct the ViewModel with them, and
   dispose it in `dispose`.
2. **A missing provider is a crash, not a fallback.** Never catch
   `ProviderNotFoundException` to substitute different behaviour. The home once
   did this for the travel plan, so a fixture that forgot the provider silently
   ran a different product. Production tests and screenshot fixtures use the
   same dependency contract `bootstrap()` does.

`bootstrap()` takes `prefs`, `speech`, `analytics`, `kana` and `words` as
test seams only. Production `main()` leaves them null.

## Testing

| Layer | What the test proves |
| --- | --- |
| ViewModel and use case | Learning decisions, without pumping a widget. Clock, random and IO contracts are injected |
| Repository and service | The public contract, the real stored format, and failure, retry and cancellation. Snapshot scope is only as far as `repository_ownership_test` names. Not the number of times a mock was called |
| Widget | Rendering, commands, navigation, injection, large text, small screens, and lifecycle events |
| Integration | The real `bootstrap()` and real plugins. Host fakes, emulator and physical-device evidence are reported separately and never substituted for each other |

`test/`, `integration_test/` and `test_driver/` are separate roles of one
package and all three stay.

Shared helpers currently live in two directories, and that is an
inconsistency rather than a rule: `test/support/` holds
`restore_recovery_test_support.dart` (37 import sites) and `test/helpers/`
holds `fake_tts_client.dart` and `kana_orthography.dart` (17 between them).
Nothing distinguishes them, and no guard enforces either. Pick one before the
split hardens; until then, put a new helper next to the ones it resembles
rather than starting a third home.

An architecture guard is only trustworthy if it has been seen to fail. When you
add one, put the violation back, watch the guard turn red, then remove it again
and record both results. A guard that has only ever been green may be scanning
nothing.

## Guards

These are the source conventions `pure_layer_imports_test` scans. Lifecycle,
snapshot identity, and immutability are not in this list.

| Rule | Guard |
| --- | --- |
| Domain imports no Flutter or `dart:ui` | the pure domain layer imports no package:flutter/* or dart:ui |
| Domain imports no UI | the domain layer never imports the UI layer |
| Data imports no use cases | the data layer never imports use_cases (the dependency points one way) |
| Data imports no UI | the data layer never imports the UI layer |
| Services import no repositories | services never import repositories (services sit below them) |
| Repositories import no repositories | a repository never reaches for another repository |
| Data has no import cycles | the data layer has no import cycles |
| ViewModels hold no widgets, timers or navigation | ViewModels hold no view dependencies (widgets, timers, or navigation) |
| Views leave evidence writes to their ViewModel | migrated feature views leave progress and analytics writes to their ViewModel |
| No provider probing | no screen invents a second product by probing for a provider |
| UI reaches platform sources only through services | the UI layer never touches platform packages directly (services wrap them) |
| Bootstrap provides every owner the UI reads | the composition root provides every owner the UI reads |

The view guard discovers its own scope: a directory counts as split into View
and ViewModel once it holds a `*_viewmodel.dart`, and every `*_screen.dart`
beside it is then checked. A new feature is covered the moment it lands, with no
list to update here.

## Where Kotonoha differs from the official sample

The [recommendations][rec] have stated strengths and conditions. These are the
places Kotonoha does not follow the sample, with the reason.

**No `go_router`.** Navigation is `Navigator` with static `route()` methods on
each screen. The app has no deep links, no web URLs and no nested navigators, so
a router would add a layer without removing one.

**No `freezed` or code generation.** Models are hand-written immutable classes.
The model count is small and stable, and every stored model needs a hand-written
honest decoder anyway: a corrupt row is dropped, never invented. Generated
`fromJson` would have to be replaced by hand in exactly those places.

**No `Result` type.** The sample returns `Result<T>` from repositories. Kotonoha
reports failure through the persistence controllers instead, because a failed
write is not a per-call error for the caller to branch on: it is an app-wide
state that raises one calm banner and stays retryable. A `Result` at each call
site would push that decision back into the callers this design deliberately
keeps it out of.

**`KanaProgressRepository` and `WordProgressRepository` are abstract
contracts.** Formal ViewModels and `bootstrap()` depend on them;
`LocalKanaProgressRepository` and `LocalWordProgressRepository` are the
production owners. The sample defines an `abstract class` for every
repository. The remaining owners here (kanji, travel, placement) are still
concrete classes; whether they get the same split is still open on
[#149](https://github.com/Koopa0/Kotonoha/issues/149).

A single implementation is not a reason to skip the contract — the sample's
own `ItineraryConfigRepository` has exactly one. But unlike the sample, where
a repository is a thin wrapper over an API, some learning rules live on the
value types these repositories apply, so a hand-written fake that
reimplements `recordAnswer` can pass tests against a schedule production no
longer uses. A fake must delegate to the real value types rather than
restate their rules. `WordStat` stays distinct from `KanaStat` /
`ReadingStat`; the two contracts are not a generic SRS engine.
