with `OVER()` clauses, not as an aggregate function in `SELECT` without `GROUP BY`. However, even that form is not universally supported in all contexts — and in this case, the query is trying to use it as an aggregate function in the `SELECT` list, which BigQuery rejects outright.

BigQuery’s correct way to compute percentiles is using the `APPROX_QUANTILES()` function for approximate percentiles (preferred for large datasets) or `PERCENTILE_CONT()` only within a window function context — but since we need exact percentiles for clinical reporting and the dataset is manageable, we can use `PERCENTILE_CONT` via `ARRAY_AGG` with `ORDER BY` and indexing, or better yet, use `APPROX_QUANTILES()` which is fully supported and efficient.

However, note: the question asks for 25th, 50th, 75th, and 95th percentiles — and `APPROX_QUANTILES()` returns an array of approximate quantiles. We can extract them by index.

But: `APPROX_QUANTILES(x, 100)` returns 101 values (0th to 100th percentile), so:
- 25th percentile → index 25
- 50th → index 50
- 75th → index 75
- 95th → index 95

We can use `APPROX_QUANTILES(total_instability_score, 100)[OFFSET(25)]` etc.

Also, note: `PERCENTILE_CONT` is not supported as an aggregate in BigQuery — so we must replace all instances.

Additionally, we should ensure that we are using `physionet-data.mimiciv_3_1_hosp` and `physionet-data.mimiciv_3_1_icu` as required — which we are.

Minor improvement: In `chart_events_filtered`, we join `d_items` from ICU module — correct. But we should ensure we are filtering for valid `valuenum` and non-null charttime — already done.

We also need to ensure that `total_instability_score` is not NULL — we are already grouping by stay_id, so NULLs are excluded.

We will replace all `PERCENTILE_CONT(..., x)` with `APPROX_QUANTILES(..., 100)[OFFSET(x*100)]` — but note: `APPROX_QUANTILES` expects the number of quantiles as the second argument. For 100 quantiles, we get 101 values (0 to 100). So:
- 25th → index 25
- 50th → index 50
- 75th → index 75
- 95th → index 95

We’ll use `APPROX_QUANTILES(total_instability_score, 100)` and extract the required indices.

We also note that `STDDEV` is supported in BigQuery — so we keep that.

We’ll also keep `AVG` for mean burden, LOS, and mortality.

Final fix: Replace all `PERCENTILE_CONT(..., x)` with `APPROX_QUANTILES(..., 100)[OFFSET(x*100)]` — but note: for 0.25, we want index 25, so `OFFSET(25)`, etc.

We’ll update the `final_results` CTE accordingly.

Let’s rewrite the final_results CTE with the corrected percentile functions.

sql
WITH asthma_diagnoses AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE (
    di.icd_code IN ('J45.901', 'J45.909', 'J44.1') -- ICD-10
    OR di.icd_code IN ('493.20', '493.21', '493.22') -- ICD-9
  )
),

icu_stays_with_age_gender AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    p.anchor_age,
    p.gender,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
),

chart_events_filtered AS (
  SELECT 
    ce.stay_id,
    ce.charttime,
    di.label,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label IN (
    'Heart Rate',
    'Systolic BP',
    'Respiratory Rate',
    'SpO2',
    'Temperature'
  )
    AND ce.valuenum IS NOT NULL
),

hourly_instability AS (
  SELECT 
    isag.stay_id,
    FLOOR(TIMESTAMP_DIFF(ce.charttime, isag.intime, SECOND) / 3600) AS hour_bin,
    SUM(
      CASE 
        WHEN ce.label = 'Heart Rate' AND (ce.valuenum < 50 OR ce.valuenum > 130) THEN 1
        WHEN ce.label = 'Systolic BP' AND (ce.valuenum < 90 OR ce.valuenum > 200) THEN 1
        WHEN ce.label = 'Respiratory Rate' AND (ce.valuenum < 8 OR ce.valuenum > 30) THEN 1
        WHEN ce.label = 'SpO2' AND ce.valuenum < 90 THEN 1
        WHEN ce.label = 'Temperature' AND (ce.valuenum < 35 OR ce.valuenum > 38.5) THEN 1
        ELSE 0
      END
    ) AS abnormal_count
  FROM icu_stays_with_age_gender isag
  JOIN chart_events_filtered ce
    ON isag.stay_id = ce.stay_id
  WHERE ce.charttime >= isag.intime
    AND ce.charttime < TIMESTAMP_ADD(isag.intime, INTERVAL 72 HOUR)
  GROUP BY isag.stay_id, FLOOR(TIMESTAMP_DIFF(ce.charttime, isag.intime, SECOND) / 3600)
),

total_instability AS (
  SELECT 
    stay_id,
    SUM(abnormal_count) AS total_instability_score
  FROM hourly_instability
  GROUP BY stay_id
),

asthma_cohort AS (
  SELECT 
    ti.total_instability_score,
    isag.los,
    isag.hospital_expire_flag
  FROM total_instability ti
  JOIN icu_stays_with_age_gender isag
    ON ti.stay_id = isag.stay_id
  JOIN asthma_diagnoses ad
    ON isag.subject_id = ad.subject_id AND isag.hadm_id = ad.hadm_id
),

age_matched_cohort AS (
  SELECT 
    ti.total_instability_score,
    isag.los,
    isag.hospital_expire_flag
  FROM total_instability ti
  JOIN icu_stays_with_age_gender isag
    ON ti.stay_id = isag.stay_id
  LEFT JOIN asthma_diagnoses ad
    ON isag.subject_id = ad.subject_id AND isag.hadm_id = ad.hadm_id
  WHERE ad.subject_id IS NULL -- exclude asthma patients
),

final_results AS (
  SELECT
    'Asthma Cohort' AS cohort,
    STDDEV(total_instability_score) AS sd_instability,
    APPROX_QUANTILES(total_instability_score, 100)[OFFSET(25)] AS p25_instability,
    APPROX_QUANTILES(total_instability_score, 100)[OFFSET(50)] AS p50_instability,
    APPROX_QUANTILES(total_instability_score, 100)[OFFSET(75)] AS p75_instability,
    APPROX_QUANTILES(total_instability_score, 100)[OFFSET(95)] AS p95_instability,
    AVG(total_instability_score) AS mean_instability_burden,
    AVG(los) AS mean_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM asthma;