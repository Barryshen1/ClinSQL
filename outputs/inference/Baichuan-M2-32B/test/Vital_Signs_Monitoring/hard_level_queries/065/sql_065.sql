with labels 'CRRT', 'Hemodialysis', or 'Peritoneal dialysis' from `inputevents` and `d_items`.
- Vital instability score: For each ICU stay, in the first 48 hours, we check hourly for abnormal vitals (tachycardia, hypotension, tachypnea, abnormal temp, hypoxemia) using `chartevents` and `d_items`. The composite score is the proportion of abnormal hours.
- 90th percentile: Computed using `APPROX_QUANTILES` for RRT patients.
- Top decile: RRT patients with composite score >= 90th percentile.
- Outcomes: For top decile RRT and non-RRT patients, we compute:
  - Hypotension hours (MAP<65) and tachycardia hours (HR>100) in entire ICU stay.
  - ICU LOS (from `icustays.los`).
  - Mortality (from `admissions.hospital_expire_flag`).
- Comparison: Grouped by RRT top decile vs non-RRT, with averages for each outcome.
- Edge cases: 
  - Multiple ICU stays: Each stay is independent.
  - Missing vitals: Hours without data are considered normal.
  - Age calculation: Uses anchor date; assumes anchor date is close to ICU admission.
- Tables: `patients`, `admissions`, `icustays` (HOSP/ICU), `chartevents`, `d_items`, `inputevents`.

SQL:;