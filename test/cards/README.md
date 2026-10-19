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

Leave out a field the card doesn't have. Comparison ignores case and punctuation; phones compare digits only.
`flutter test test/parser/ground_truth_test.dart` prints per-field accuracy; targets are enforced once 40 cards are present.

Real cards hold other people's personal data. Keep this folder out of any public repo (it is in `.gitignore` except this README).
