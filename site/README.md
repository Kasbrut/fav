# FAV website

The website is plain static HTML and is intended for GitHub Pages. English
content lives in `en/`; future translations should use sibling locale folders
such as `it/` with the same filenames and heading IDs. Shared presentation and
brand assets live in `assets/`.

Serve the `site/` directory locally to check relative links:

```bash
python3 -m http.server --directory site 4173
```

The root page currently sends visitors to English. Replace that redirect with
a small language chooser when another locale is added. Keep the site free of
analytics, cookies, remote fonts and third-party runtime scripts.

The bundled Atkinson Hyperlegible webfonts are licensed under the SIL Open Font
License 1.1. The license text is stored beside the font files.
