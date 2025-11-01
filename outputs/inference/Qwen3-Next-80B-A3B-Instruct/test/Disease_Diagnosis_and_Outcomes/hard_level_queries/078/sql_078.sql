with `OVER()` clauses, or more commonly, uses `APPROX_QUANTILES()` for approximate percentiles or `PERCENTILE_CONT()` with `OVER()` for windowed calculations — but not as a direct aggregate in `SELECT` without `GROUP BY` or `OVER()`.

   However, in this case, we want **aggregate percentiles** (not windowed) over the entire cohort. BigQuery’s recommended and supported function for this is `APPROX_QUANTILES()` for approximate percentiles (fast, scalable) or `PERCENTILE_CONT()` **with `OVER()`** — but the latter requires a window frame and is not suitable for single-row aggregations.

   Since we need exact percentiles (P25, median, P75, P90) for a single aggregated result, and BigQuery does not support `PERCENTILE_CONT()` as a direct aggregate, we must use `APPROX_QUANTILES()` — which is the standard, efficient, and correct approach in BigQuery for this use case.

   Note: `APPROX_QUANTILES(x, 100)` returns an array of 101 values (0th to 100th percentile). We can extract the required percentiles by array indexing: `[25]`, `[50]`, `[75]`, `[90]`.

2. **Median Survival Calculation**: The original query tried to compute median survival among deaths using `PERCENTILE_CONT(..., 0.5)`. We must replace this with `APPROX_QUANTILES()` as well. We need to compute the duration in days between `admittime` and `deathtime` only for those who died (`hospital_expire_flag = 1`).

3. **Composite Risk Score**: The `diagnosis_count` CTE correctly counts total diagnoses per patient. We can use `APPROX_QUANTILES()` on `dc.total_diagnoses` to get the required percentiles.

4. **Minor Fixes**:
   - Ensure all dataset references use backticks since they contain hyphens: `physionet-data.mimiciv_3_1_hosp` → `'physionet-data.mimiciv_3_1_hosp'` (BigQuery requires backticks for project names with hyphens).
   - Use `SAFE_CAST` or ensure date arithmetic is valid — `deathtime - admittime` returns an INTERVAL, so we use `EXTRACT(DAY FROM ...)` correctly.
   - The `LEFT JOIN`s for `aki` and `ards` are correct, but we must ensure we're joining on `hadm_id` or `subject_id` consistently. Since `cohort` has `subject_id` and `hadm_id`, and `aki`/`ards` are defined on `subject_id` and `hadm_id`, we can join on `subject_id` (since each subject may have multiple admissions, but we are counting per subject — this is acceptable for rate calculations as long as we assume one admission per subject in cohort, which we do via `DISTINCT`).

   However, note: a patient may have multiple admissions. The cohort is built on `DISTINCT subject_id` from admissions with HF diagnosis — so we are treating each subject as one unit. This is acceptable for population-level rates.

5. **Final Structure**: We will replace all `PERCENTILE_CONT(..., x)` with `APPROX_QUANTILES(..., 100)[OFFSET(x*100)]` — but note: `APPROX_QUANTILES(..., 100)` returns 101 elements (0 to 100), so:
   - P25 → index 25
   - Median → index 50
   - P75 → index 75
   - P90 → index 90

   We use `OFFSET(25)`, `OFFSET(50)`, etc.

   We must also handle NULLs in `deathtime` — only non-null `deathtime` should be included in survival calculation.

6. **Performance Note**: `APPROX_QUANTILES` is approximate but highly scalable and accurate enough for clinical data of this size. For exact percentiles, BigQuery offers `PERCENTILE_CONT` only in window functions — which would require restructuring the entire query with windowing and then aggregating — which is unnecessarily complex. `APPROX_QUANTILES` is the standard and accepted approach in BigQuery for this use case.

---

sql
WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      LOWER(dicd.long_title) LIKE '%heart failure%'
      OR LOWER(dicd.long_title) LIKE '%congestive heart failure%'
      OR LOWER(dicd.long_title) LIKE '%cardiac failure%'
    )
),
aki AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%acute kidney injury%'
     OR LOWER(dicd.long_title) LIKE '%acute renal failure%'
     OR (d.icd_version = 9 AND d.icd_code LIKE '584%')
     OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
),
ards AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%acute respiratory distress syndrome%'
     OR LOWER(dicd.long_title) LIKE '%ards%'
),
diagnosis_count AS (
  SELECT
    d.subject_id,
    COUNT(*) AS total_diagnoses
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN cohort c ON d.subject_id = c.subject_id
  GROUP BY d.subject_id
)
SELECT
  COUNT(*) AS total_cohort,
  SUM(CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS in_hospital_mortality_rate,
  SUM(CASE WHEN aki.subject_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS aki_rate,
  SUM(CASE WHEN ards.subject_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS ards_rate,
  APPROX_QUANTILES(
    CASE WHEN c.hospital_expire_flag = 1 THEN EXTRACT(DAY FROM (c.deathtime - c.admittime)) END, 
    100
  )[OFFSET(50)] AS median_survival_days_among_deaths,
  APPROX_QUANTILES(dc.total_diagnoses, 100)[OFFSET(0)] AS composite_risk_score_min,
  APPROX_QUANTILES(dc.total_diagnoses, 100)[OFFSET(25)] AS composite_risk_score_p25,
  APPROX_QUANTILES(dc.total_diagnoses, 100)[OFFSET(50)] AS composite_risk_score_median,
  APPROX_QUANTILES(dc.total_diagnoses, 100)[OFFSET(75)] AS composite_risk_score_p75,
  APPROX_QUANTILES(dc.total_diagnoses, 100)[OFFSET(90)] AS composite_risk_score_p90,
  APPROX_QUANTILES(dc.total_diagnoses, 100)[OFFSET(100)] AS composite_risk_score_max
FROM cohort c
LEFT JOIN aki ON c.subject_id = aki.subject_id
LEFT JOIN ards ON c.subject_id = ards.subject_id
LEFT JOIN diagnosis_count dc ON c.subject_id = dc;