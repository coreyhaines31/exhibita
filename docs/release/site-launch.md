# Launching exhibitaformac.com

The site in `site/` is built and checked locally (`make lint`) but not deployed. Everything below is public or costs money, so each step waits for Corey's approval. Do them in this order.

## 1. Before launch day

- [ ] If `docs/samples/app/` is re-rendered again before launch, re-export the screenshots in `site/src/assets/shots/` (they already show the final `#b42ee8` light): `cwebp -q 82 -resize 1200 0 docs/samples/app/editor-applied-light.png -o site/src/assets/shots/editor-applied-light.webp`, and the same for `editor-applied-dark`, `editor-marked-light`, `panel-history-*` (no resize), `docs/samples/all-marks.png` and `docs/samples/cli-demo.png` (`-resize 1140 0`). Look at each one.
- [ ] Corey approves the "Why it exists" paragraph on the homepage (it is a draft in his voice, like the other drafts in `mac-app-kit/site-kit/sections/maker-copy.md`).
- [ ] Recheck every claim against what was verified live (`docs/product/unit*-live-checklist.md`). The copy states only what the code does; it gives no timings and names no tested clients on purpose.

## 2. Vercel project (team `coreys-apps`)

```sh
cd site
vercel link --scope coreys-apps --project exhibita     # create the project when asked
```

- Root directory `site`, framework "Other". `vercel.json` already sets `buildCommand: make lint`, no install step, `outputDirectory: dist`, trailing slashes and immutable caching for `/_a/`.
- Production branch `main`. Deploy production from `main` only, never from `development` or a feature branch: merge `development` into `main` first, then `vercel --prod` from a clean checkout of `main` (or let the Git integration build `main`).
- Add the domains `exhibitaformac.com` and `www.exhibitaformac.com` to the project, with `www` redirecting to the apex like the sibling sites.

## 3. DNS for exhibitaformac.com

Point the domain at Vercel at its registrar (the `namecheap` MCP can do it if the domain is there):

- Apex `@`: `A` record `76.76.21.21`.
- `www`: `CNAME` `cname.vercel-dns.com`.

Then wait for Vercel to show both domains as valid, and check `https://exhibitaformac.com/` and `/privacy/` load with the certificate.

## 4. Analytics (site only, never the app)

Siblings load TracerKit, which loads Headstream (and Fathom on some), with one script tag in `base.html`'s head (Kill Cord: `<script async src="https://tracerkit.com/t.js" data-key="tk_...">`).

- [ ] Request a TracerKit site key for `exhibitaformac.com` and a Headstream property under it.
- [ ] Add the one script tag to `site/src/layouts/base.html`, before `</head>`.
- [ ] Rewrite the "exhibitaformac.com" section of `site/src/pages/privacy/index.html`: it currently says the site sets no cookies and loads no analytics. Use Kill Cord's wording (`killcord/site/src/pages/privacy/index.html`, section "killcord.app") as the model.

## 5. At release: switch the calls to action

When v1 is notarized and the cask is in `coreyhaines31/homebrew-tap`:

- Replace each `<span class="bx-btn soon-btn">Coming soon</span>` (header, hero, "Get Exhibit A") with a download link to `https://github.com/coreyhaines31/exhibita/releases/latest/download/ExhibitA.dmg` (match the DMG name `Scripts/release.sh` produces), as Kill Cord's `{{download_url}}` does.
- Add "View source" links to `https://github.com/coreyhaines31/exhibita` once the repo is public, in the hero, "Get Exhibit A" and the footer links.
- Add the Homebrew block under the hero and "Get Exhibit A": `brew install --cask coreyhaines31/tap/exhibit-a` (the cask draft is `Scripts/homebrew/exhibit-a.rb`).
- Change the "Get Exhibit A" heading from "Coming soon." to an install line, the FAQ "When can I get it?" answer, the og card's foot line (`site/scripts/og.html`, then `make images`), and the index description in `site/src/pages.json`.
- Add `downloadUrl` back to the `SoftwareApplication` data in `site/scripts/build.py`.

## 6. The nine sibling sites

Each sibling lists the family in a "More free Mac apps" section and in its footer. Add Exhibit A to both, as "coming soon" until release, then as a normal link. Each change is a production deploy of that site, so each needs Corey's approval, and each ships from that repo's `main` (client-style repos with `cf/development` deploy as their own notes say).

Copy `mac-app-kit/site-kit/family/exhibit.webp` into each site's family icon folder first.

"More free Mac apps" card (site-kit's `.bx-apps .soon` style, last in the `.bx-apps` grid):

```html
<div class="soon"><img src="/family/exhibit.webp" alt="" width="56" height="56"><div><b>Exhibit A<em>Coming soon</em></b><span>Mark up a screenshot in a few keystrokes</span></div></div>
```

Footer item (site-kit's `.bx-family .soon` style, last in the `.bx-family` list):

```html
<li class="soon"><img src="/family/exhibit.webp" alt="" width="56" height="56">Exhibit A<small>Coming soon</small></li>
```

Adjust the image path to each site's own (`/family/`, `/images/family/` or `/assets/family/`), and the footer grid to ten columns (five on phones), as `site/src/assets/styles.css` here does. At release, swap both for links to `https://exhibitaformac.com`.

| App | Repo | Where to edit |
|---|---|---|
| Fuel Gauge | `~/code/fuelgauge` | `site/src/`: the apps section of the homepage and the footer layout |
| Spare | `~/code/spare` | `site/`: homepage apps section and footer |
| Disk Forecast | `~/code/diskforecast` | `site/`: homepage apps section and footer |
| Midnight Oil | `~/code/midnightoil` | `site/`: homepage apps section and footer |
| WiFi or ISP | `~/code/wifiorisp` | `site/`: homepage apps section and footer |
| Green Room | `~/code/greenroom` | `site/`: homepage apps section and footer |
| On Hand | `~/code/onhand` | `site/`: homepage apps section and footer |
| Coat Check | `~/code/coatcheck` | `site/src/`: homepage apps section and footer |
| Kill Cord | `~/code/killcord` | `site/src/pages/index.html` (`#apps`) and `site/src/layouts/footer.html` |

Also add Exhibit A to `mac-app-kit/site-kit/sections/apps.html` and `family-footer-item.html` so new sites start with ten.

## 7. After launch

- Submit `https://exhibitaformac.com/sitemap.xml` to Google Search Console and Bing.
- Check the page in a real browser at desktop and phone widths, light and dark.
