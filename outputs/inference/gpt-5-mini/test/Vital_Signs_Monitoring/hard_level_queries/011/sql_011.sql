WITH instability_items AS (
  -- find itemids whose label mentions "instability" (adjust pattern if your score has a different name)
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%instability%'
),

first24_instability AS (
  -- maximal instability numeric value within first 24 hours of each ICU stay
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    MAX(ce.valuenum) AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  JOIN instability_items di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    -- inside first 24 hours of ICU stay
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),

pneumonia_admissions AS (
  -- admissions with any diagnosis whose long_title mentions pneumonia
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
   AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%pneumonia%'
),

cohort AS (
  -- attach patient/admission/icu metadata, restrict to female age 55-65 and pneumonia admissions
  SELECT
    f24.subject_id,
    f24.hadm_id,
    f24.stay_id,
    f24.instability_score,
    p.gender,
    p.anchor_age,
    a.deathtime,
    a.hospital_expire_flag,
    icu.intime,
    icu.outtime,
    icu.los
  FROM first24_instability f24
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON f24.subject_id = icu.subject_id
   AND f24.hadm_id = icu.hadm_id
   AND f24.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON f24.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f24.hadm_id = a.hadm_id
  JOIN pneumonia_admissions pn
    ON f24.hadm_id = pn.hadm_id
  WHERE LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 55 AND 65
),

with_rank AS (
  -- compute cohort size, number <= 60 and decile (NTILE 10 descending for "most unstable" = decile 1)
  SELECT
    c.*,
    COUNT(*) OVER () AS cohort_n,
    SUM(CASE WHEN instability_score <= 60 THEN 1 ELSE 0 END) OVER () AS n_le_60,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile_desc
  FROM cohort c
)

-- final output: percentile of 60 among cohort, and stats for the most unstable decile (decile_desc = 1)
SELECT
  'percentile_of_60' AS metric,
  ROUND(100.0 * MAX(n_le_60) / NULLIF(MAX(cohort_n), 0), 2) AS percentile_of_60,
  MAX(cohort_n) AS cohort_size,
  NULL AS decile_size,
  NULL AS mean_los_days,
  NULL AS median_los_days,
  NULL AS icu_mortality_pct
FROM with_rank

UNION ALL

SELECT
  'top_decile' AS metric,
  NULL AS percentile_of_60,
  MAX(cohort_n) AS cohort_size,
  COUNT(*) AS decile_size,
  -- mean ICU LOS (days)
  ROUND(AVG(los), 2) AS mean_los_days,
  -- approximate median ICU LOS in the top decile
  (SELECT APPROX_QUANTILES(los, 2)[OFFSET(1)] FROM with_rank WHERE decile_desc = 1) AS median_los_days,
  -- ICU mortality percent: admissions.deathtime between ICU intime and outtime
  ROUND(100.0 * SUM(CASE WHEN deathtime IS NOT NULL AND deathtime BETWEEN intime AND outtime THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS icu_mortality_pct
FROM with_rank
WHERE decile_desc = 1;