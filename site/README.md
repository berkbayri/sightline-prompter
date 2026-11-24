# sightlineprompter.app source

Static landing page, 11 locales, built into `docs/` (GitHub Pages serves `main:/docs`).

```sh
python3 site/build.py      # writes docs/index.html, docs/<locale>/index.html, sitemap.xml, robots.txt, 404.html
```

Do not edit generated files in `docs/` by hand. `docs/images/` and `docs/release/` are never touched. `docs/privacy.html`, `terms.html` and `support.html` are generated from `site/pages/*.html`; an existing hand-written page is only replaced with `python3 site/build.py --replace-pages`.

## Layout

- `site/template.html`: one page template, `{{key}}` placeholders, `{{{raw}}}`, `{{#list}}...{{/list}}` loops, `{{^x}}` inverse. `site/partials/top.html` and `foot.html` (nav, footer, consent bar) and `site/page.html` (long-form pages, English only) share the chrome.
- `site/i18n/<locale>.json`: all visible copy and meta per locale. `en.json` is the source of truth; every locale has exactly the same keys.
- `site/assets/`: `site.css` (design tokens + components), `site.js` (reading demo, case tabs, consent, language memory), `fonts/`, `img/`.

## Locales

| code | path | html lang | hreflang |
|---|---|---|---|
| en | `/` | en | en, x-default |
| tr | `/tr/` | tr | tr |
| de | `/de/` | de | de |
| es | `/es/` | es | es |
| fr | `/fr/` | fr | fr |
| it | `/it/` | it | it |
| pt-br | `/pt-br/` | pt-BR | pt-BR |
| ja | `/ja/` | ja | ja |
| ko | `/ko/` | ko | ko |
| zh-hans | `/zh-hans/` | zh-Hans | zh-Hans |
| zh-hant | `/zh-hant/` | zh-Hant | zh-Hant |

## Copy keys (i18n JSON shape)

```json
{
  "meta": { "title": "", "description": "", "og_title": "", "og_description": "", "og_image_alt": "" },
  "nav": { "iphone": "", "mac": "", "languages": "", "faq": "", "download": "", "language_menu": "" },
  "hero": {
    "lines": ["previous line", "current line, read word by word", "next line"],
    "sub": "",
    "cta_secondary": ""
  },
  "devices": { "kicker_cue": "[[one script]]", "title": "", "title_accent": "", "body": "", "mac_label": "", "iphone_label": "", "demo_script": "3 short sentences read on both devices" },
  "cases": {
    "title": "", "title_accent": "",
    "items": [
      { "id": "youtube", "tab": "", "title": "", "body": "", "alt": "" },
      { "id": "reels", "tab": "", "title": "", "body": "", "alt": "" },
      { "id": "course", "tab": "", "title": "", "body": "", "alt": "" },
      { "id": "meeting", "tab": "", "title": "", "body": "", "alt": "" }
    ]
  },
  "crop": { "title": "", "title_accent": "", "body": "", "tags": ["", "", ""] },
  "languages": { "title": "", "title_accent": "", "body": "", "note": "" },
  "library": { "title": "", "title_accent": "", "body": "", "cue_example": "", "cue_note": "", "formats_label": "" },
  "pro": { "title": "", "free_title": "", "free_items": [""], "pro_title": "", "pro_items": [""], "note": "" },
  "faq": { "title": "", "items": [ { "q": "", "a": "" } ] },
  "close": { "title": "", "title_accent": "", "sub": "" },
  "footer": { "privacy": "", "terms": "", "support": "", "rights": "" },
  "consent": { "text": "", "accept": "", "decline": "", "settings": "" },
  "store": { "badge_alt": "Download on the App Store", "badge_lang": "en-us" }
}
```

## Analytics

GA4 web stream (site only, separate from the app's stream) with Consent Mode v2: everything `denied` by default, the bar sets `analytics_storage` on accept. The choice is stored in `localStorage` (`sp-consent`). Measurement ID lives in `site/build.py` (`GA_ID`). Events: `app_store_click` (param `placement`), `case_tab` (param `case`), `language_switch`.
