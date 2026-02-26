# REQUIREMENTS.md — SEED7

## Current Features

### Navigation
- [x] Fixed top nav with backdrop blur
- [x] Active state highlighting on current page
- [x] Mobile hamburger menu with toggle
- [x] Arabic / English language toggle pill in nav
- [x] Smooth scroll on all internal anchors

### Homepage (`index.html`)
- [x] Hero section — headline, subtitle, Arabic name origin card
- [x] Scroll cue animation (pulsing line)
- [x] "The Pattern" section — US/China comparison, KSA thesis ("The Flip" animation)
- [x] Ecosystem Maturity section — building blocks narrative
- [x] "What We Do" section — studio model, 2 key facts
- [x] Portfolio grid — 7 company logo cards, each linking to portfolio page anchors
- [x] Team teaser section — link to full team page
- [x] CTA footer bar — "For Investors" + "For Founders" buttons
- [x] Scroll-triggered reveal animations (IntersectionObserver)
- [x] Radial gradient background on hero

### Portfolio Page (`portfolio.html`)
- [x] Jump pill navigation at top (quick links to each company)
- [x] Per-company sections: logo, category tag, tagline, description
- [x] Company-specific gradient accent backgrounds
- [x] "Visit [Company]" external links
- [x] 7 companies documented: HudHud, Barq, Awaed, Jazi, Lobah, SaudiEye, Dahna

### Team Page (`team.html`)
- [x] Grid of team cards — photo, name, title, bio, LinkedIn button
- [x] 4 partners documented

### Contact Page (`contact.html`)
- [x] "For Investors" — mailto CTA for investor deck (`investors@seed7.me`)
- [x] General contact form (name, email, message)
- [x] Thank-you state shown after form submission (client-side only)
- [x] Direct email fallback (`contact@seed7.me`)
- [x] "For Investor" / "For Founder" query-param pre-selection (`?type=investor|founder`)

### Bilingual Support
- [x] Full Arabic mirrors of all pages (`-ar.html` suffix)
- [x] RTL layout throughout Arabic pages
- [x] Language toggle in nav on every page

### Meta / SEO
- [x] Open Graph tags (title, description, image, url)
- [x] Twitter card meta tags
- [x] `og-image.png` social share image
- [x] Deployed at `seed7.me` with clean URLs

---

## Known Gaps / Open Issues

### Contact Form
- [ ] **No backend** — the contact form shows a thank-you state client-side but does not actually submit to any server or email service. Messages are silently dropped.
- [ ] No form validation feedback beyond browser-native `required` attribute

### Portfolio
- [ ] Some company logos (Barq, Awaed, Jazi, Lobah, SaudiEye) are loaded from `seed7.me/assets/` — external dependency, not bundled in repo
- [ ] Dahna has no external website link yet (company in build)
- [ ] No company stat metrics shown (stat markup present but empty in several companies)

### Performance
- [ ] No image optimization pipeline — logos served as raw PNG/WebP
- [ ] No bundling or minification (acceptable for static site of this size)
- [ ] Google Fonts loaded via CDN — adds render-blocking request

### Infrastructure
- [ ] No custom domain SSL config in repo (managed via Railway/registrar)
- [ ] No analytics (no GA, Plausible, or similar)
- [ ] No sitemap.xml or robots.txt

### Content
- [ ] Arabic pages may lag behind English pages on content updates (manual sync required)
- [ ] No blog or news section
- [ ] No press/media kit page
