# Memo: Where Kestrel Fibre loses sales value, and what to change first

**To:** Head of Sales · **From:** Sales Process & Enablement (portfolio exercise) · **Data:** Jan-2024 to Aug-2026, synthetic
**Status:** Recommendations for pilots, not final decisions. All data is synthetic (see README).

## The short version
Headline sales look healthy. Four of five teams are above quota in 2026 and order volume is growing. But **the revenue
that stays is leaking in three places the quota report doesn't show**: field sales churn after the sale, long installation
waits in the North West, and discounts above 10% that don't win extra deals. None of these needs new headcount to fix.

## What the data shows

1. **Field sales hit quota but keep the least revenue.** Field North keeps 78% of ordered MRR at day 90 and Field South 82%,
   vs 90% for telesales. Door-to-door customers churn in their first 90 days at 11.3% vs 4.2% elsewhere. 31% of those
   early churners say they did not understand the contract terms.
2. **Long install waits cause cancellations, and the North West has them.** Orders waiting 22+ days cancel at 15–20%,
   vs 6% for waits of 14 days or less. The average North West wait has gone from ~14 to ~26 days. Its cancellation rate
   has doubled, costing ~42 orders (~£18k/year of revenue) in the last 12 months.
3. **Discounts above 10% are margin given away.** Going from 0% to 10% adds ~8 points of win rate in door-to-door.
   Going beyond 10% adds nothing measurable, but costs ~£50k/year.
4. **Quotas are out of line with lead supply.** Outbound's quota rose 15% in 2026 while its leads fell ~17%, so attainment
   fell from 113% to 81%. Business Development hit 185% in 2025, meaning its quota was set too low.

## What I recommend (in order)

| # | Action | Cost | How we'll know it worked (8–12 weeks) |
|---|---|---|---|
| 1 | Weekly "at-risk orders" list: every order with an install slot >21 days gets a proactive call. Take the North West numbers to Operations. | Low: one report, some agent time | Cancellation rate for 22+ day orders; North West wait |
| 2 | Pilot a 48-hour welcome call plus a 90-day retention element in commission in **one** field team; the other is the control. | Low–medium | 90-day churn and % MRR retained, pilot vs control |
| 3 | Pilot a 10% discount cap (approval above it) in one field team. | None | Average discount ↓; win rate within 2 points of control |
| 4 | Set 2027 quotas from lead supply and ramp status, not a flat % uplift. | Analyst time | Share of rep-months at quota similar across teams |

## What I'm not sure about
- The install-wait link is an association from historical data. Customers with long waits might differ in other ways.
  The proactive-call pilot is how we test cause.
- For discounts, the data can't rule out a small (≤2 point) win-rate effect above 10%. That's why this is a pilot
  with a guardrail, not a rule.
- The capacity planner uses historical leads per rep, which reflects lead supply more than true rep capacity.
  I'd want call and visit activity data before using it for hiring decisions.

*Supporting detail: README §3–4, `sql/04`, `sql/05`, `sql/07`, `sql/08`, Excel dashboard tabs Team_Quota, Process, Discount.*
