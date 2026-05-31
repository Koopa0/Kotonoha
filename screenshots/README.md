# Screenshots

The README files reference these images. Drop real captures here with these
exact names so they render on GitHub:

| File | Screen |
|---|---|
| `01-home.png` | Home — progress ring + today's session |
| `02-session.png` | A question inside today's session |
| `03-reading.png` | Reading practice (a word revealed) |
| `04-progress.png` | Progress — accuracy + status breakdown |

Capture from a device (the kana need a real Japanese font, so emulator/headless
renders won't do):

```bash
flutter run --release          # on a connected phone
adb exec-out screencap -p > screenshots/01-home.png   # Android
```

Keep them portrait and roughly phone-sized; GitHub will scale them in the table.
