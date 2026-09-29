# Interview prep: questions this project will attract

Short, honest answers. Know the numbers, but know the *reasoning* better.

**1. "The data is synthetic. Didn't you just find what you put in?"**
Partly, yes, and I say so in the README. The point is the method. The analysis also had to deal with things I didn't
simply read back. Rep skill is hidden (not in the export), so rep comparisons are noisy. Door-to-door reps discount more,
so a pooled discount comparison is confounded, which is why I compare within source. Recent customers haven't had 90 days
yet, so churn needs a cohort cut-off. And one "significant" discount result (Inbound, p = 0.046) was a false positive
that the Bonferroni correction caught. With real data, I'd expect messier effects and would start by validating definitions.

**2. Why is win rate calculated on closed deals only?**
Open deals haven't had an outcome yet. Counting them as losses understates win rate, and more so for channels with long
cycles (Partner: median 26 days vs 1 day for door-to-door). Formula: won / (won + lost).

**3. Why median sales cycle, not mean?**
Cycle times are right-skewed. A few deals that sit for months pull the mean up. The median describes the typical deal.

**4. Why is team attainment SUM(actual)/SUM(quota) and not the average of rep percentages?**
A rep on a 25% ramp quota who sells a little can show 200% and distort a simple average. The ratio of sums weights each
rep by the size of their quota. I also show the share of rep-months at or above quota, because the ratio of sums can
hide a team where a few people carry everyone.

**5. Why 90-day churn, and why only customers activated ≥ 90 days ago?**
Early churn is the churn a salesperson can influence (mis-selling, misunderstood terms). Later churn is more about
product, price and competitors. Including recent customers would count them as "not churned" before they've had the
chance to churn. That's censoring bias, and it makes recent periods look better than they are.

**6. Does install wait *cause* cancellations?**
I can't prove it from historical data. What I can say is: the relationship is strong, it's dose-response (longer wait →
more cancellations), it holds after controlling for channel, segment and region (OR 1.53 per week), and it explains the
North West's problem (region OR 0.96 after controlling for wait). There's a plausible mechanism: customers accept a
competitor's earlier slot. To test cause: a before/after when North West capacity is added, or randomise the
proactive-call intervention.

**7. Correlation vs association vs causation, in one line each?**
Correlation: a measured linear co-movement between two numeric variables. Association: any statistical relationship,
including between categories (e.g. wait band and cancellation). Causation: changing X changes Y. That needs an experiment
or a credible design (natural experiment, before/after with a control), not just a relationship in historical data.

**8. Why not just say "discounts don't work"?**
Because they do up to 10%. The 0→10% step adds ~8 points of win rate in door-to-door. Beyond 10% I found no effect, but the
confidence interval (−4.2 to +1.9 points) can't rule out a small one. So I recommend a pilot with a guardrail, not a rule.

**9. Why Holt-Winters? Is a 4.7% MAPE good?**
I compared three methods on the same 6-month holdout, including a seasonal-naive baseline. A forecast that can't beat
"same month last year" isn't adding value. Holt-Winters won (4.7% vs 6.2% and 7.1%). The caveat is that one holdout
is a small test. A rolling-origin backtest would be more reliable. I also excluded Jan-2024 because the data starts
mid-pipeline, and that month looks artificially low.

**10. What are the limits of your capacity planner?**
It uses historical leads handled per rep. That mostly reflects how many leads we *gave* reps, not how many they *could*
handle. For real headcount decisions I'd want activity data: calls per hour, visits per day, talk time.

**11. What would you do in your first month here with real data?**
Agree definitions with Sales Ops first: what's a won deal, when quota credit happens, how lead source is attributed.
Then reconcile my numbers to the numbers people already trust before presenting anything new. Only then look for leaks.

**12. Did you use AI tools?**
Yes. I used AI coding assistants to speed up writing code and drafting documentation, the same way I use them at work.
I made the analytical decisions, I checked the results (SQL and pandas reconcile, Excel matches Python), and I can
explain every number. *(Only say this if it's true in your own words. Walk through every script before the interview.)*

**13. Why did you build the synthetic data instead of using a public dataset?**
Public sales datasets are overused and rarely have the structure of a telecom sales operation (lead → opportunity →
order → install → billing, with quotas and reps). Generating it let me model realistic problems, including dirty
exports, and be transparent about exactly what is and isn't real.

## Numbers worth remembering
Win rate 38% · Referral 55% / Outbound 22% · door-to-door 90-day churn 11.3% vs 4.2% · field teams keep 78–82% of ordered
MRR at 90 days vs 90% telesales · cancellation 6% (≤14-day wait) → 20% (29+ days) · OR 1.53 per week of wait ·
discount 0→10% +8 pts, 10→15%+ no effect · Outbound attainment 113% → 81% · new reps close at ~0.7× · forecast
~2,275 orders over 6 months, MAPE 4.7%.
