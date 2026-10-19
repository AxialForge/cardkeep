# OCR ground-truth set (spec §12)

Target mix (40 cards): 10 plain, 8 dark/coloured, 6 glossy, 6 vertical, 5 two-sided, 5 non-English or two-language.

Each card is three files sharing an id (`c001`, `c002`, …):

| File | What |
|---|---|
| `c001.jpg` | the photo (back side: `c001b.jpg`) |
| `c001.ocr.json` | ML Kit output captured on a phone, `{"lines":[{"text","left","top","width","height","confidence"}]}` |
| `c001.json` | ground truth, written by hand |

```json
{
  "region": "US",
  "kind": "plain",
  "fields": {
    "name": "Dana Reyes",
    "title": "VP Procurement",
    "company": "Northwind Forging, Inc.",
    "email": "dana.reyes@northwindforging.com",
    "mobile": "+13305550101",
    "office": "+13305550199",
    "website": "www.northwindforging.com",
    "address": "1200 Industrial Pkwy, Suite 4, Streetsboro, OH 44241"
  }
}
```

## Capturing on the phone

1. Install the debug build: `flutter install` (or copy `build/app/outputs/flutter-apk/app-debug.apk` to the phone).
2. The app opens on **OCR capture (debug)**. Set the phone region, then **Pick photos** (several at once) or **Take photo**.
3. For each photo it writes `cNNN.jpg`, `cNNN.ocr.json` and `cNNN.draft.json` (parser output) to
   `Internal storage/Android/data/com.axialforge.card_organizer/files/ocr_capture`.
4. Copy that folder's files here over USB (or `adb pull /sdcard/Android/data/com.axialforge.card_organizer/files/ocr_capture/. test/cards`).
5. Correct each draft against the photo, set `kind`, and rename it `cNNN.json`. Drafts are ignored by the test.

Leave out a field the card doesn't have. Comparison ignores case and punctuation; phones compare digits only.
`flutter test test/parser/ground_truth_test.dart` prints per-field accuracy; targets are enforced once 40 cards are present.

Real cards hold other people's personal data. Keep this folder out of any public repo (it is in `.gitignore` except this README).
