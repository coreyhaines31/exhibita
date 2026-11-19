# exhibitaformac.com

The static site for https://exhibitaformac.com, generated from shared layouts. The app lives one folder up. Built the same way as the sibling sites (Kill Cord's is the model).

## Editing

- `src/layouts/base.html`: document head, metadata and the self-hosted fonts snippet from `mac-app-kit/site-kit/sections/fonts.html`. `header.html` and `footer.html` are the shared header and footer (with the family panel).
- `src/pages/`: page content inside the main element. `src/pages.json`: titles, descriptions, and `updated` dates for the sitemap.
- `src/assets/`: styles, icons, fonts, screenshots, the social card, and robots.txt.

Run `make build` to generate `dist/`, or `make lint` to build and check structure, alt text, title and description lengths, em dashes, "open source", internal links, and assets. `make images` re-renders the social card from `scripts/og.html` and the touch icon from the mac-app-kit icon (`ICON_SRC` overrides its path). The build uses Python's standard library only.

The look is the Mac app family's Brushed design: `src/assets/brushed.css`, `fonts/` and `family/` are copied from `mac-app-kit/site-kit` (edit them there, then copy them in), and `styles.css` maps this site's sections onto them. Exhibit A's purple `#b42ee8` appears only as pilot lights.

Screenshots in `src/assets/shots/` are WebP copies of the committed offscreen renders in `docs/samples/app/` and `docs/samples/`. When those renders change, re-export them (`cwebp -q 82 -resize 1200 0 in.png -o out.webp`).

Copy rules: no em dashes anywhere user-facing, "free, source available" (never "open source"), and only what the app does today. Exhibit A is unreleased: the call to action is "Coming soon" and there is no download or GitHub link yet. `docs/release/site-launch.md` lists what changes at launch.

## Preview

```sh
make build && python3 -m http.server 4721 -d dist
```

## Hosting

Not deployed yet. Planned: Vercel (team `coreys-apps`, project `exhibita`, root directory `site`) runs `make lint` and serves `dist/`. Deploy production from `main` only.
