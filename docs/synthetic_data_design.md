# Synthetic Data Design

Why synthetic: real CRM, quota and churn data is confidential, and public "sales" datasets (e.g. Superstore) have
no funnel stages, quotas, installation process or churn. A documented generator lets the project show end-to-end sales
analytics on a realistic data model, and anyone can check whether the analysis recovers what was built in.

**Fictional company:** Kestrel Fibre, a small UK full-fibre provider (an "altnet"). Window: leads created
1-Jan-2024 → 31-Aug-2026; snapshot date 31-Aug-2026. Random seed fixed (`20260929`), so every run is identical.

## Organisation
| Team | Channel | Starting reps | Handles |
|---|---|---:|---|
| Telesales Inbound | Telesales | 8 | Web, Inbound Call, Referral (residential) |
| Telesales Outbound | Telesales | 5 | Outbound Call (connected calls) |
| Field North | Field Sales | 5 | Door-to-door: North West, Yorkshire & NE, Scotland |
| Field South | Field Sales | 5 | Door-to-door: London, South East, Midlands |
| Business Development | Business Development | 3 | Partner and business web leads |

Monthly attrition probability 2.5% (~26%/year), each leaver replaced 2–6 weeks later.

## Behavioural assumptions encoded
| Area | Assumption | Why plausible |
|---|---|---|
| Lead volume | Source-specific base volume, growth (Web +1.2%/month, Outbound −0.8%/month) and seasonality (Sep/Jan peaks, Aug/Dec dips; door-to-door follows the weather) | Moving-home season, outbound lists degrade over time |
| Lead → opp | Referral 62%, Inbound Call 60%, Door-to-Door 55%, Web 38%, Outbound 16% | Intent differs by source |
| Win probability | Source base rate × discount effect × rep ramp × hidden rep skill | See below |
| Discount effect | Win-probability multiplier 1.00 / 1.08 / 1.15 / 1.16 / 1.16 for 0/5/10/15/20% | Diminishing returns on price |
| Rep ramp | ×0.72 in the first 90 days, ×0.88 at 90–180 days | New starters learn the product |
| Rep skill | Hidden per-rep multiplier (σ = 0.10). **Not exported**, so the analysis cannot see it | Real performance variance |
| Loss stage | Door-to-door losses skew to Credit Check; Outbound to Quote Sent | Doorstep signing before a credit check; cold prospects drop at price |
| Install wait | Regional baselines 9–15 days; **North West rises by ~13 days from Jan-2025 to mid-2026** | Build/engineer capacity constraints are common for altnets |
| Cancellation | Probability rises smoothly with wait (logistic curve centred at 24 days), +4 pp for door-to-door | Customers cancel during long waits; cooling-off period |
| Churn | Monthly hazard 0.7% residential / 0.4% business; **+3.5 pp/month in the first 3 months for door-to-door** (+0.6 pp otherwise); spikes at contract end | Doorstep sales carry more early regret; out-of-contract switching |
| Quotas | Team base = 2024 median of fully-ramped rep-months; +6% (2025), +15% (2026); ramp 25/50/75% for months 1–3 | Flat top-down uplifts are a common real-world practice |

## Defects injected into the raw exports
Exact duplicates · test records (rep R999) · dd/mm/yyyy dates in an ISO column · 24 spelling variants of regions and
sources · "£" inside numeric fields · lower-case product names · out-of-range discounts (150, −10, 100) · blank loss
reasons · close dates before created dates · churn dates before activation dates.

## What the analysis had to work out (not handed to it)
- Rep skill is hidden, so rep comparisons contain real unexplained noise.
- The discount effect is confounded with channel (field reps discount more), which requires within-source comparison.
- The North West effect is *mediated* by wait time. The logistic model has to separate "region" from "wait".
- Recent cohorts are censored for churn and cancellation.
- The generator contains **no** discount effect beyond 10% for any source. The Inbound Call p = 0.046 result is therefore
  a genuine false positive, and the multiple-comparison correction correctly rejects it.

## Honest framing
The findings are consistent with the generator because they were built in. What the project demonstrates is the
workflow for finding, testing, quantifying and communicating such effects on messy data without being fooled by
confounding, censoring or chance.
