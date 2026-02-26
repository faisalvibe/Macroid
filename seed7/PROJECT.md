# PROJECT.md — SEED7

## What It Is

SEED7 is a venture studio that co-creates and scales technology companies in Saudi Arabia. The studio pairs capital with hands-on operational partnership — assembling teams, shaping strategy, and funding visions from a blank page.

This repo is the **marketing website** for SEED7 (`seed7.me`), presenting the studio's thesis, portfolio, team, and contact channels.

## Core Thesis

Every major economy follows the same arc: oil and banks dominate, then technology takes over. The US did it. China did it. Saudi Arabia — the last major emerging market — has already begun. SEED7 is positioned at that inflection point.

---

## Tech Stack

| Concern | Choice |
|---------|--------|
| Pages | Pure HTML5 — no framework |
| Styling | Vanilla CSS (CSS variables, `clamp()`, grid, flexbox) |
| Font | Inter via Google Fonts |
| Animations | Vanilla JS (IntersectionObserver, scroll events) |
| Hosting | Railway (`seed7-production.up.railway.app`) |
| Static server | `serve` v14 (Node.js) |
| Config | `serve.json` — clean URLs, no directory listing |
| Languages | English (default) + Arabic (RTL mirrors, `-ar.html` suffix) |

## Site Architecture

```
Seed7/
├── index.html / index-ar.html        # Homepage: thesis, pattern, portfolio teaser
├── portfolio.html / portfolio-ar.html # 7 portfolio companies in detail
├── team.html / team-ar.html          # 4 partners with bios
├── contact.html / contact-ar.html    # Investor deck request + contact form
├── seed7-logo.svg                    # Primary logo
├── og-image.png                      # Open Graph / social share image
├── photo 1.png.webp                  # Faisal Alkhamissi photo
├── logos/                            # Company logos + ecosystem logos
├── package.json                      # Node — only dependency: serve
└── serve.json                        # Static server config
```

## Pages

| Page | Purpose |
|------|---------|
| `index.html` | Hero, KSA tech thesis ("The Pattern"), ecosystem maturity, studio model, portfolio grid, team teaser, CTA |
| `portfolio.html` | Full detail on each of the 7 portfolio companies |
| `team.html` | Partner profiles with bios and LinkedIn links |
| `contact.html` | Investor deck request (mailto) + general contact form |

## Portfolio Companies

| Company | Sector | Tagline | URL |
|---------|--------|---------|-----|
| HudHud | Deep-Tech / Maps | The Google Maps of Saudi Arabia | hudhud.sa |
| Barq | Fintech / Payments | Saudi Arabia's leading digital payments app | barq.com |
| Awaed | Fintech / Investing | First commission-free trading platform | awaed.capital |
| Jazi | Fast Fashion | Ultra-fast fashion, designed for the Kingdom | jazi.com |
| Lobah | Gaming | Saudi Arabia's leading gaming studio | lobah.com |
| SaudiEye | Space-Tech | Saudi Arabia's Own Eyes in Space | sarsatx.com |
| Dahna | Enterprise Data & AI | Enterprise Data & AI for Saudi Arabia | — (in build) |

## Team

| Partner | Background |
|---------|-----------|
| Faisal Alkhamissi | Chairman & Partner — 20+ yrs, Mozat founder (8M users), eWTP Arabia Capital GP |
| Muteb Alqani | Partner — PayFort/Amazon alum, CEO SAFCSP |
| Sultan Ghaznawi | Partner — investor, Chairman Scene Holding |
| Faris Alamoudi | Partner — investment banking, $20B+ in structured transactions |

## Deployment

- Hosted on **Railway** — auto-deploys from `main`
- Entry point: `npm start` → `serve -l $PORT -c serve.json`
- Domain: `seed7.me` (prod), `seed7-production.up.railway.app` (Railway URL)
