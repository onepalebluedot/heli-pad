# HeliPad website

A static, single-page site for the closed alpha. No build step: `index.html`,
`assets/styles.css`, `assets/app.js`, and web-sized images in `assets/img/`.
Fonts come from Google Fonts and icons from Lucide on jsDelivr.

Preview locally:

```bash
python3 -m http.server 8765
```

The phone screens are HTML re-creations of the Go and Plan tabs, drawn with the
app's own `HeliColors` values, so they stay sharp at any size and can animate.
The `ChatGPT Image …png` files are the full-size originals; the page only loads
the resized copies in `assets/img/`.

`assets/img/helipad-logo-v2.png` is the master logo. `app-icon.png`,
`apple-touch-icon.png`, `favicon.png`, `helipad-wordmark.png` and the iOS
`AppIcon.png` are cut from it: the round mark on the app's ivory (`#f6f4ed`),
opaque because iOS rejects app icons with transparency.

## Alpha sign-up

The form posts `{ name, email }` as JSON to the URL in the form's
`data-endpoint` attribute, which points at `POST /v1/alpha-signup` on the family
API (`../family-api`). That route stores one row per email in
`helipad_alpha_signup`, created by the API's schema on first request. It has to
be deployed before the form works; until then submissions show an error.

Read the list:

```sql
SELECT name, email, created_at FROM helipad_alpha_signup ORDER BY created_at;
```
