# Google Sans

Served from this origin rather than from `fonts.googleapis.com`.

## Why not the CDN

Same font either way — Google Sans is licensed under the SIL Open Font License, and these `.woff2`
files are the ones the Google Fonts API hands out. What changes is who learns about the reader.

Linking the CDN sends every visitor's IP address and referring page to Google, on a site whose
argument is that Google can read your Drive and we cannot read your vault. It is also a live GDPR
question in the EU after the Munich regional court's 2022 ruling on embedded Google Fonts, and it
costs two DNS lookups and two TLS handshakes before any text can paint.

If you want the CDN version instead, delete these files and put the standard `<link>` tags back in
`src/layouts/Base.astro`. Nothing else depends on the choice.

## The files

Latin and Latin-Extended subsets, upright and italic, variable across weights 400–700 with an
optical-size axis. Four files, roughly 55KB each, and a browser fetches only the subsets it needs.

Refreshing them:

```sh
curl -s -A "Mozilla/5.0 ... Chrome/120.0 Safari/537.36" \
  "https://fonts.googleapis.com/css2?family=Google+Sans:ital,opsz,wght@0,17..18,400..700;1,17..18,400..700&display=swap"
```

The user agent matters — without a modern one, Google serves `.ttf` instead of `.woff2`. Pull the
`latin` and `latin-ext` `src:` URLs out of the response and download those, then check the
`unicode-range` values in `src/styles/global.css` still match.

## Licence

SIL Open Font License 1.1. See <https://openfontlicense.org>. The OFL permits redistribution and
web embedding; it does not permit selling the fonts on their own, which nobody here is doing.
