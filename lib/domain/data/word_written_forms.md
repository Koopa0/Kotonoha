# Japanese spelling and travel reading contexts

A learner who meets `くうこう / kuukou / 機場` needs to recognise **空港**
on a sign. The Chinese gloss cannot serve as Japanese orthography: 車站 is 駅,
飛機 is 飛行機, and even shared words can use different glyphs (學校 → 学校).

Every entry in `kWords` and `kPhrases` explicitly supplies a `writtenForm`.
It is a curated, display-only everyday spelling, not a conversion of the Traditional Chinese
meaning and not an exhaustive dictionary of alternative spellings.

- Use Japanese kanji and okurigana where appropriate: 空港, 学校, 食べる.
- Keep ordinary kana spellings where appropriate: ください, きれい, コーヒー.
  Letter sizes use the labels encountered on clothing: S, M, L.
- When the existing entry combines meanings with different spellings, show
  short Traditional Chinese sense labels, e.g. 紙（紙）・髪（頭髮） and
  止まる（停下）・泊まる（過夜）. Do not imply those are interchangeable spellings.
- Render the labelled 日文寫法 block automatically after reveal in 渡し舟,
  黙読, 聞き取り and 文字起こし. Do not put it behind the optional false-friend
  note or expose it during a blind audio/reading prompt.

The kana prompt, TTS input, answer tiles, readability gate and `word:<kana>`
identity are unchanged. Phrases likewise retain their `phrase:<kana>`
identities. No progress migration or kanji-track mastery credit is involved. Recognising the spelling is exposure, not a new tested skill; this
display does not claim to measure kanji recall.

## Practice beyond exposure

Kana phrases reveal the same utterance in everyday Japanese spelling: for
example, えきは どこ → 駅はどこ and カードは つかえません → カードは使えません.
Negative forms, particles and polite endings must agree with the kana prompt.
The 124 phrases include six new airport and onward-transport utterances.

The transport scene includes 空港, 飛行機 and 両替 plus those six phrases. They
follow the existing kana-readability and introduction-before-review rules.

`kTravelReadings` adds 18 original mixed-script sentences to the existing
kanji curriculum. 空港, 飛行機, 荷物, 改札, 予約, 両替, 乗り換え and お土産 each
have two contexts. Compound readings stay on whole ruby segments; okurigana
stays outside the annotated segment. Existing sentence order is preserved.
The harvested `unit:<written>#<reading>` records and `sentence:<written>`
records use the existing kanji practice and scheduling paths. Seeing a word
or kana phrase never grants progress to these separate reading records.

A singleton kanji review may lack distractors in both its session and the
character inventory. In that case, the quiz view model retries with the
production sentence corpus, so one visible answer cannot count as recall.

## Content reference checks

The airport example was checked against the [Immigration Services Agency's
plain-Japanese Narita page](https://www.moj.go.jp/isa/about/region/narita/plain_japanese.html),
which pairs 空港 with くうこう and 飛行機 with ひこうき. The Japan Foundation's
[Irodori lesson 13](https://www.irodori.jpf.go.jp/assets/data/bn/pdf/strarter/X_L13_Bengali.pdf)
also uses 空港 in a real transport question. These are checks of the motivating
examples, not a claim that those pages validate every corpus entry.

## Regression coverage

`word_dataset_test.dart` checks explicit coverage of the entire corpus,
representative Japanese/Chinese differences, homophones, kana-only forms and
unchanged progress/gating identities. `word_written_form_flow_test.dart` uses
production dataset entries and screens to check hidden-before-reveal,
shown-after-reveal, next-item reset, TTS input, retained progress after reload,
correct/incorrect dictation, and 320px layouts with 2x text. These are host widget
tests with simulated speech; they do not certify physical-device audio or
human retention.

`phrase_written_form_flow_test.dart` checks revealed short sentences, negative
forms, speech input and progress identity at 320px with 2x text.
`travel_written_bridge_test.dart` checks corpus alignment, independent IDs,
scene inclusion and scheduling. `travel_scene_entry_test.dart` opens the real
transport entry and reaches the airport word and phrase.
`travel_reading_flow_test.dart` exercises introduction, independent kanji
recall with distractors, persistence and untouched word progress. Removing
the singleton fallback makes the 荷物 recall test fail because only one
answer remains.
