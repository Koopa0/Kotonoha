# Word spelling at reveal

A learner who meets `くうこう / kuukou / 機場` needs to recognise **空港**
on a sign. The Chinese gloss cannot serve as Japanese orthography: 車站 is 駅,
飛機 is 飛行機, and even shared words can use different glyphs (學校 → 学校).

Every entry in `kWords` explicitly supplies `Word.writtenForm`. It is a curated,
display-only everyday spelling, not a conversion of the Traditional Chinese
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
identity are unchanged. No progress migration or kanji-track mastery credit is
involved. Recognising the spelling is exposure, not a new tested skill; this
change does not claim to measure kanji recall.

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
