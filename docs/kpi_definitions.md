# KPI Definitions

For each KPI: the exact formula, why it was chosen, how to read it, its main limitation, and what a stakeholder should
do with it. The same definitions are used in SQL, Python, Excel and the Tableau guide.

---

### 1. Lead → Opportunity conversion
**Formula:** leads that became an opportunity ÷ all leads, grouped by *lead created date*.
**Why:** separates lead *quality* (did the lead qualify?) from *selling* effectiveness (win rate). A low figure points to targeting or lead routing, not to the sales pitch.
**Read it as:** Outbound converts 15.6%, Referral 62.8%. The two sources play different roles, so compare each source with its own history.
**Limitation:** the latest 1–2 weeks are understated because those leads have not been worked yet.
**Action:** low conversion on a paid source is a marketing conversation; a falling trend on a stable source is a lead-handling conversation (speed to contact).

### 2. Win rate
**Formula:** Won ÷ (Won + Lost). **Open opportunities are excluded.**
**Why excluded:** open deals have not had the chance to be won yet. Including them makes every recent period look worse, which is a common dashboard error.
**Read it as:** of the deals that finished, the share we won.
**Limitation:** "Lost" depends on reps closing out dead deals. Stale open deals inflate win rate by hiding losses. Monitor open-deal age.
**Action:** compare within a source over time and between reps on the same source. Comparing reps across sources is unfair.

### 3. Sales cycle
**Formula:** **median** days from opportunity created to order placed, for won deals.
**Why median:** cycle times are right-skewed. One 90-day leased-line deal moves the average a lot but barely moves the median.
**Limitation:** 36 records with a close date before their creation date are excluded because the true date is unknown.
**Action:** a lengthening cycle on a stable source is an early warning of a process blockage (credit checks, survey slots).

### 4. Average deal size (MRR per order) and TCV
**Formula:** ordered net MRR (after discount) ÷ orders. TCV = MRR × contract months.
**Why MRR:** broadband revenue is recurring; one-off order value misrepresents it.
**Limitation:** business leased lines (£250 MRR) distort blended averages, so always split by segment.

### 5. Quota attainment
**Formula:** SUM(ordered MRR) ÷ SUM(quota) for the team and period. Part-month stubs (< £50) are excluded.
**Why SUM/SUM:** averaging each rep's percentage gives a rep who worked 3 days the same weight as a full-month rep.
**Also shown:** share of rep-months at or above quota. Healthy quota design usually puts roughly 50–70% of reps at quota; 90% suggests the quota is too easy, 30% suggests it is unrealistic.
**Limitation:** measured on *ordered* MRR (assumed company policy), so it is blind to cancellations and early churn. That is why KPI 7 exists.

### 6. Pre-install cancellation rate
**Formula:** orders cancelled before installation ÷ **resolved** orders (activated + cancelled).
**Why resolved only:** orders still waiting for installation have an unknown outcome.
**Action:** a rising rate in long-wait bands is an operations-capacity problem that shows up in sales numbers.

### 7. Share of ordered MRR retained at 90 days (sale quality)
**Formula:** MRR from orders that activated **and** were still billing 90 days later ÷ ordered MRR. Orders up to Apr-2026 only, so every order has had time to reach day 90.
**Why:** it translates "a sale" into "revenue that stayed", a quality-adjusted output measure.
**Action:** candidate component for incentive design; compare teams on the same basis.

### 8. 90-day (early-life) churn
**Formula:** customers who churned within 90 days of activation ÷ customers activated ≥ 90 days before the snapshot.
**Why the eligibility rule:** without it, customers activated last month would count as "retained" only because they have not had time to churn (right-censoring).
**Read it as:** a signal of expectation-setting at the point of sale. Later churn is more about price and competition.

### 9. Monthly churn rate
**Formula:** customers who churned in month *m* and were active at its start ÷ customers active at the start of month *m*.
**Limitation:** expect spikes around contract end (months 12 and 24); read the trend, not single months.

### 10. MRR bridge
**Formula:** New MRR (activations) − Churned MRR = Net new MRR; Ending MRR = cumulative sum.
**Limitation:** covers customers acquired since Jan-2024 only.

### 11. Stage-weighted pipeline
**Formula:** Σ open-deal MRR × historical probability of winning from its current stage (last 12 months).
**Limitation:** residential cycles are days long, so the open pipeline is small and weighted pipeline matters mainly for Business Development.

### 12. Forecast accuracy (MAPE)
**Formula:** mean of |forecast − actual| ÷ actual over the 6-month holdout.
**Why MAPE plus bias:** MAPE is easy to explain to sales leaders ("off by ~5% a month"). Bias shows whether a model systematically over- or under-forecasts, which matters for capacity planning.
