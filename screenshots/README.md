# Screenshots

The README files reference these images. They're produced by the capture
harness, which seeds progress so every track is populated:

```sh
flutter drive --driver=test_driver/screenshot.dart \
  --target=integration_test/screenshot_capture.dart -d emulator-5554
```

| File | Screen |
|---|---|
| `01-home.png` | Home — 言の葉 wordmark, progress ring, 今日の稽古 |
| `02-session.png` | A question inside 今日の稽古 (the adaptive session) |
| `03-dictation.png` | 文字起こし — assemble the heard word from kana tiles |
| `04-progress.png` | 歩み — accuracy + per-kana status |
| `05-kanji.png` | 漢字の声 — a kanji reading revealed |
| `06-sentence.png` | 黙読 — a short phrase revealed |
| `07-kanji-sentence.png` | 名残の仮名 — a kanji sentence with fading furigana |
| `08-ferry.png` | 渡し舟 — the kana inked in over the audio |

The bundled Klee One font renders the kana, so the emulator capture above is
fine. Keep them portrait and phone-sized; GitHub scales them in the table.
