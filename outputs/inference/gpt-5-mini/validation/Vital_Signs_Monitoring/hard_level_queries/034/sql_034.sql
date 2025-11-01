with two or more distinct diagnosis titles containing 'shock' */
WITH shock_hadm AS (
  -- find hadm_id with two or more distinct shock-related diagnosis long_titles
  SELECT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(COALESCE(dd.long_title, '')) LIKE '%shock%'
  GROUP BY
    d.hadm_id
  HAVING
    COUNT(DISTINCT dd.long_title) >= 2
),

map_itemids AS (
  -- candidate MAP itemids by label lookup
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(COALESCE(label, '')) LIKE '%mean arterial%'
    OR LOWER(COALESCE(label, '')) LIKE '%map%'
),

hr_itemids AS (
  -- candidate Heart Rate itemids by label lookup
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(COALESCE(label, '')) LIKE '%heart rate%'
    OR LOWER(COALESCE(label, '')) LIKE '%hr%'
),

cohort_stays AS (
  -- ICU stays for female patients aged 60-70 in admissions flagged as mixed shock
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON s.subject_id = a.subject_id
      AND s.hadm_id = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON s.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    AND s.hadm_id IN (SELECT hadm_id FROM shock_hadm)
),

-- Aggregate abnormal MAP/HR counts in the first 48 hours of ICU stay
first48_obs AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    cs.los,
    cs.hospital_expire_flag,
    COALESCE(SUM(CASE
      WHEN ce.itemid IN (SELECT itemid FROM map_itemids)
       AND ce.valuenum IS NOT NULL
       AND ce.valuenum < 65 THEN 1 ELSE 0 END), 0) AS count_map_low,
    COALESCE(SUM(CASE
      WHEN ce.itemid IN (SELECT itemid FROM hr_itemids)
       AND ce.valuenum IS NOT NULL
       AND ce.valuenum > 100 THEN 1 ELSE 0 END), 0) AS count_hr_high
  FROM
    cohort_stays cs
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON ce.subject_id = cs.subject_id
      AND ce.hadm_id = cs.hadm_id
      AND ce.stay_id = cs.stay_id
      AND ce.charttime BETWEEN cs.intime AND TIMESTAMP_ADD(cs.intime, INTERVAL 48 HOUR)
  GROUP BY
    cs.subject_id, cs.hadm_id, cs.stay_id, cs.los, cs.hospital_expire_flag
),

per_stay AS (
  -- per-stay derived fields
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    los,
    hospital_expire_flag,
    count_map_low,
    count_hr_high,
    (COALESCE(count_map_low, 0) + COALESCE(count_hr_high, 0)) AS instability_score,
    CASE WHEN COALESCE(count_map_low, 0) > 0 THEN 1 ELSE 0 END AS any_map_low,
    CASE WHEN COALESCE(count_hr_high, 0) > 0 THEN 1 ELSE 0 END AS any_hr_high
  FROM first48_obs
),

percentiles AS (
  -- approximate percentiles for instability score across the cohort
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS p95_instability,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_instability
  FROM per_stay
)

-- Final comparisons: cohort vs top decile (instability_score >= 90th percentile)
SELECT
  'cohort' AS group_label,
  COUNT(*) AS n_stays,
  ROUND(100.0 * SUM(any_map_low) / COUNT(*), 2) AS pct_with_hypotension_MAP_lt_65_first48h,
  ROUND(100.0 * SUM(any_hr_high) / COUNT(*), 2) AS pct_with_tachycardia_HR_gt_100_first48h,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS pct_inhospital_mortality,
  percentiles.p95_instability
FROM
  per_stay
CROSS JOIN
  percentiles

UNION ALL

SELECT
  'top_decile' AS group_label,
  COUNT(*) AS n_stays,
  ROUND(100.0 * SUM(any_map_low) / COUNT(*), 2) AS pct_with_hypotension_MAP_lt_65_first48h,
  ROUND(100.0 * SUM(any_hr_high) / COUNT(*), 2) AS pct_with_tachycardia_HR_gt_100_first48h,
  ROUND(AVG(los), 2) AS mean_icu_los_days,
  ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS pct_inhospital_mortality,
  percentiles.p95_instability
FROM
  per_stay
CROSS JOIN
  percentiles
WHERE
  instability_score >= percentiles.p90_instability;