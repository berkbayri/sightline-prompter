# Site glossary

One term per concept per locale. Use these in `site/i18n/*.json`; do not mix variants inside a locale.

| Locale | teleprompter | voice following | delivery cue (`[[...]]`) | notch | library (scripts) | crop guide (9:16) |
|---|---|---|---|---|---|---|
| en | teleprompter | voice following | delivery cue | notch | script library | crop guide |
| tr | teleprompter | sesle takip | anlatım notu | çentik | metin kitaplığı | kırpma kılavuzu |
| de | Teleprompter | Mitlaufen per Stimme | Vortragshinweis | Notch | Skriptbibliothek | Zuschnittrahmen |
| es | teleprompter | seguimiento de voz | indicación de lectura | muesca | biblioteca de guiones | guía de recorte |
| fr | téléprompteur | suivi vocal | indication de diction | encoche | bibliothèque de textes | guide de recadrage |
| it | teleprompter | (segue la tua voce) | nota di lettura | tacca | libreria di copioni | guida di ritaglio |
| pt-br | teleprompter | acompanhamento de voz | indicação de leitura | notch | biblioteca de roteiros | guia de corte |
| ja | テレプロンプター | 声に合わせて進む | 話し方のメモ | ノッチ | 原稿ライブラリ | クロップガイド |
| ko | 텔레프롬프터 | 목소리 따라가기 | 말하기 메모 | 노치 | 원고 보관함 | 크롭 가이드 |
| zh-hans | 提词器 | 语音跟读 | 提示 | 刘海 | 稿件库 | 裁切参考线 |
| zh-hant | 提詞機 | 語音跟讀 | 提示 | 瀏海 | 稿件庫 | 裁切參考線 |

## Rules that apply to every locale

- Brand and product names are written exactly: iPhone, iPad, Mac, MacBook, iCloud, App Store, YouTube, TikTok, DualSense, ProRes, Sightline Prompter, Sightline Pro. JSON never stores them in uppercase; CSS uppercases display headings and `build.py` marks brands `lang="en"`.
- Display headings (`*.title` + `*.title_accent`, `close.*`) are stored in sentence case. CSS adds the uppercase, so Turkish gets a correct dotted/dotless I.
- No prices. 4K, HDR and ProRes are Pro only. No "first", "only", "patented", "AI", "revolutionary", no claim about hiding from screen sharing, no invented reviews or counts.
- Turkish: apostrophe before suffixes (iPhone'da, Mac'te, iCloud'da, Pro'da); TDK spellings (çevrimdışı, bir şey, her şey).
- German: du form, nouns capitalized. French: no-break space before `: ; ? !`, vous form. Spanish: tú form, `¿ ¡` pairs, "la App Store". Italian and Portuguese: informal "tu"/"você". Japanese: です・ます. Korean: 해요체.
- Hero lines (`hero.lines`) are user-approved and locked.
