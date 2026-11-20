# Editing the site

- Copy (text) lives in `site/i18n/<code>.json`, one file per locale, same keys in all 11. Page structure lives in `site/template.html`; styles in `site/assets/` (`site.css`, `editorial.css`), demos in `site/assets/site.js`.
- Never edit `docs/` by hand: it is generated and the next build overwrites it.
- Build with `python3 site/build.py` (never `--replace-pages`), then commit `site` and `docs` together.
