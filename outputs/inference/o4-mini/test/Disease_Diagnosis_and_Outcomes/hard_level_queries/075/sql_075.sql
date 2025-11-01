WITH
-- 1. Base cohort: female, 44-54
base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
),

-- 2. Intracranial hemorrhage cohort
ich AS (
  SELECT DISTINCT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.deathtime,
    b.hospital_expire_flag
  FROM
    base AS b
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON b.subject_id = d.subject_id
     AND b.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
      ON d.icd_code    = dicd.icd_code
     AND d.icd_version = dicd.icd_version
  WHERE
    LOWER(dicd.long_title) LIKE '%intracranial hemorrhage%'
),

-- 3. Dummy major complications flag per admission (all zero)
comp AS (
  SELECT
    hadm_id,
    0 AS has_major_complication
  FROM
    base
),

-- 4. Combine cohorts with risk and complications
enriched AS (
  SELECT
    co.subject_id,
    co.hadm_id,
    co.cohort_name,
    rs.risk_score,
    rs.risk_percentile,
    IF(
      co.deathtime IS NOT NULL
      AND DATE_DIFF(co.deathtime, co.dischtime, DAY) <= 90,
      1, 0
    ) AS died_within_90d,
    IF(
      co.hospital_expire_flag = 0,
      DATE_DIFF(co.dischtime, co.admittime, DAY),
      NULL
    ) AS los_survivor,
    c.has_major_complication
  FROM (
    SELECT subject_id, hadm_id, admittime, dischtime, deathtime, hospital_expire_flag, 'ICH' AS cohort_name
    FROM ich
    UNION ALL
    SELECT subject_id, hadm_id, admittime, dischtime, deathtime, hospital_expire_flag, 'ALL' AS cohort_name
    FROM base
  ) AS co
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.risk_scores` AS rs
    ON co.subject_id = rs.subject_id
   AND co.hadm_id    = rs.hadm_id
  LEFT JOIN comp AS c
    ON co.hadm_id = c.hadm_id
)

-- 5. Final aggregation
SELECT
  cohort_name,
  -- Risk score median and IQR
  APPROX_QUANTILES(risk_score, 100)[OFFSET(50)] AS median_risk_score,
  APPROX_QUANTILES(risk_score, 100)[OFFSET(25)] AS risk_score_q1,
  APPROX_QUANTILES(risk_score, 100)[OFFSET(75)] AS risk_score_q3,
  -- 90-day mortality rate
  ROUND(100 * AVG(died_within_90d), 2) AS pct_90d_mortality,
  -- Major complication rate (dummy = 0)
  ROUND(100 * AVG(has_major_complication), 2) AS pct_major_complication,
  -- Median survivor LOS
  APPROX_QUANTILES(los_survivor, 100)[OFFSET(50)] AS median_survivor_los,
  -- Median risk percentile only for ICH cohort
  CASE
    WHEN cohort_name = 'ICH'
    THEN APPROX_QUANTILES(risk_percentile, 100)[OFFSET(50)]
    ELSE NULL
  END AS median_risk_percentile
FROM
  enriched
GROUP BY
  cohort_name
ORDER BY
  cohort_name DESC;