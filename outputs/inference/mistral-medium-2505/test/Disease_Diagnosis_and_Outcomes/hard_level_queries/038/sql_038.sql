WITH
-- Define the general male inpatient cohort (74-84 years)
general_male_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN a.deathtime IS NOT NULL AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30day
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
),

-- Define AKI cohort (using ICD codes)
aki_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN a.deathtime IS NOT NULL AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30day,
    -- Get risk scores from ICU data if available
    (SELECT MAX(valuenum) FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
     JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
     WHERE ce.hadm_id = a.hadm_id
     AND (di.label LIKE '%SAPS-II%' OR di.label LIKE '%SOFA%')) AS risk_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND (d.icd_code LIKE '584.%' OR d.icd_code LIKE 'N17.%') -- AKI ICD codes
),

-- Calculate ARDS rates for both cohorts
ards_rates AS (
  SELECT
    'General Male' AS cohort,
    COUNT(DISTINCT CASE WHEN d.icd_code LIKE '518.81' OR d.icd_code LIKE 'J80%' THEN a.hadm_id END) AS ards_count,
    COUNT(DISTINCT a.hadm_id) AS total_count
  FROM
    general_male_cohort a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id

  UNION ALL

  SELECT
    'AKI Male' AS cohort,
    COUNT(DISTINCT CASE WHEN d.icd_code LIKE '518.81' OR d.icd_code LIKE 'J80%' THEN a.hadm_id END) AS ards_count,
    COUNT(DISTINCT a.hadm_id) AS total_count
  FROM
    aki_cohort a
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
),

-- Calculate survivor LOS for both cohorts
survivor_los AS (
  SELECT
    'General Male' AS cohort,
    AVG(los_days) AS avg_los,
    PERCENTILE_CONT(los_days, 0.5) AS median_los
  FROM
    general_male_cohort
  WHERE
    mortality_30day = 0
  GROUP BY
    cohort

  UNION ALL

  SELECT
    'AKI Male' AS cohort,
    AVG(los_days) AS avg_los,
    PERCENTILE_CONT(los_days, 0.5) AS median_los
  FROM
    aki_cohort
  WHERE
    mortality_30day = 0
  GROUP BY
    cohort
)

-- Final results
SELECT
  -- AKI cohort metrics
  (SELECT PERCENTILE_CONT(risk_score, 0.5) FROM aki_cohort WHERE risk_score IS NOT NULL) AS median_risk_score,
  (SELECT PERCENTILE_CONT(risk_score, 0.25) FROM aki_cohort WHERE risk_score IS NOT NULL) AS risk_score_q1,
  (SELECT PERCENTILE_CONT(risk_score, 0.75) FROM aki_cohort WHERE risk_score IS NOT NULL) AS risk_score_q3,
  (SELECT AVG(mortality_30day) FROM aki_cohort) AS aki_30day_mortality,

  -- ARDS rate comparison
  (SELECT ards_count/total_count FROM ards_rates WHERE cohort = 'General Male') AS general_ards_rate,
  (SELECT ards_count/total_count FROM ards_rates WHERE cohort = 'AKI Male') AS aki_ards_rate,

  -- Survivor LOS comparison
  (SELECT avg_los FROM survivor_los WHERE cohort = 'General Male') AS general_avg_los,
  (SELECT median_los FROM survivor_los WHERE cohort = 'General Male') AS general_median_los,
  (SELECT avg_los FROM survivor_los WHERE cohort = 'AKI Male') AS aki_avg_los,
  (SELECT median_los FROM survivor_los WHERE cohort = 'AKI Male') AS aki_median_los,

  -- Risk percentile for the entire AKI cohort
  (SELECT PERCENT_RANK() OVER(ORDER BY risk_score) FROM aki_cohort WHERE risk_score IS NOT NULL) AS risk_percentile;