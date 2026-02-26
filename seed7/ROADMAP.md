# ROADMAP.md — SEED7

## Phase 1 — Fix Critical Gaps (Now)

These are blocking issues that affect real user experience or data loss.

- [ ] **Fix the contact form** — wire it to a real backend (Formspree, Resend, or a simple Railway endpoint). Currently messages are silently dropped.
- [ ] **Bundle external assets** — download Barq, Awaed, Jazi, Lobah, SaudiEye logos from `seed7.me/assets/` into the `logos/` folder so the site has no external image dependencies.
- [ ] **Add sitemap.xml** — helps search indexing for all 8 HTML pages (4 EN + 4 AR).
- [ ] **Add robots.txt** — minimal file, allow all.

---

## Phase 2 — Polish & Analytics

- [ ] **Add web analytics** — Plausible (privacy-friendly) or GA4. Track page views, investor CTA clicks, founder CTA clicks.
- [ ] **Dahna website link** — once Dahna has a live site, add the visit button.
- [ ] **Fill in company stats** — the stat cards on the portfolio page have markup but most companies have empty values. Populate with real traction numbers.
- [ ] **OG image per page** — currently all pages share the same `og-image.png`. A portfolio-specific and team-specific image would improve link previews.
- [ ] **Arabic content parity** — audit `index-ar.html`, `portfolio-ar.html`, etc. against English versions and sync any lagging content.

---

## Phase 3 — Content Expansion

- [ ] **Press / media kit page** — downloadable logo pack, brand guidelines, press contacts.
- [ ] **News / updates section** — lightweight announcements (new portfolio company, funding news). Could be a simple static JSON file rendered client-side.
- [ ] **Investor materials page** (gated or ungated) — pitch deck embed or protected download link.
- [ ] **Portfolio company pages (deep-links)** — currently each company links out to its own site. Consider adding richer in-site profiles if external sites don't exist yet (e.g., Dahna).

---

## Phase 4 — Infrastructure Improvements

- [ ] **Image optimization** — run logos and photos through squoosh/sharp, convert to WebP where not already done.
- [ ] **Self-host fonts** — download Inter from Google Fonts and serve locally to remove render-blocking CDN request.
- [ ] **CDN / caching headers** — update `serve.json` with proper cache-control for static assets (logos, images) vs HTML pages.
- [ ] **CI/CD** — add a simple GitHub Actions workflow: validate HTML, check all external links, auto-deploy to Railway on `main` push.
