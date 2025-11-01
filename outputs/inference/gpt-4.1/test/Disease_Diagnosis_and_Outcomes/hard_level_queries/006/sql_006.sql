WITH lower_gi_bleed_admissions AS (
  -- Identify admissions for lower GI bleeding in females aged 70-80
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.anchor_age,
    p.gender,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND (
      LOWER(dd.long_title) LIKE '%lower%' AND LOWER(dd.long_title) LIKE '%bleed%'
      OR LOWER(dd.long_title) LIKE '%rectal%' AND (LOWER(dd.long_title) LIKE '%bleed%' OR LOWER(dd.long_title) LIKE '%hemorrhage%')
      OR LOWER(dd.long_title) LIKE '%colon%' AND (LOWER(dd.long_title) LIKE '%bleed%' OR LOWER(dd.long_title) LIKE '%hemorrhage%')
      OR LOWER(dd.long_title) LIKE '%gastrointestinal%' AND (LOWER(dd.long_title) LIKE '%bleed%' OR LOWER(dd.long_title) LIKE '%hemorrhage%')
      OR LOWER(dd.long_title) LIKE '%melena%'
      OR LOWER(dd.long_title) LIKE '%hematochezia%'
      OR LOWER(dd.long_title) LIKE '%hemorrhage%' AND (LOWER(dd.long_title) LIKE '%rectum%' OR LOWER(dd.long_title) LIKE '%anus%')
    )
),
major_complications AS (
  -- Identify major complications per admission
  SELECT
    d.hadm_id,
    COUNT(DISTINCT d.icd_code) AS n_major_complications
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      LOWER(dd.long_title) LIKE '%sepsis%'
      OR LOWER(dd.long_title) LIKE '%shock%'
      OR LOWER(dd.long_title) LIKE '%failure%'
      OR LOWER(dd.long_title) LIKE '%arrest%'
      OR LOWER(dd.long_title) LIKE '%infarction%'
      OR LOWER(dd.long_title) LIKE '%embolism%'
      OR LOWER(dd.long_title) LIKE '%thrombosis%'
      OR LOWER(dd.long_title) LIKE '%perforation%'
      OR LOWER(dd.long_title) LIKE '%peritonitis%'
    )
  GROUP BY d.hadm_id
),
admissions_with_risk AS (
  -- Merge cohort with risk score
  SELECT
    l.subject_id,
    l.hadm_id,
    l.admittime,
    l.dischtime,
    l.deathtime,
    l.anchor_age,
    l.gender,
    l.dod,
    COALESCE(m.n_major_complications, 0) AS risk_score,
    CASE WHEN COALESCE(m.n_major_complications, 0) > 0 THEN 1 ELSE 0 END AS has_major_complication
  FROM
    lower_gi_bleed_admissions l
    LEFT JOIN major_complications m
      ON l.hadm_id = m.hadm_id
),
quintiles AS (
  -- Assign quintiles by risk score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM
    admissions_with_risk
),
outcomes AS (
  -- Calculate outcomes per admission
  SELECT
    *,
    -- 90-day mortality: death within 90 days of admission
    CASE
      WHEN deathtime IS NOT NULL AND DATETIME_DIFF(deathtime, admittime, DAY) <= 90 THEN 1
      WHEN dod IS NOT NULL AND DATETIME_DIFF(DATETIME(dod), admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS died_within_90d,
    -- LOS in days
    SAFE_CAST(DATETIME_DIFF(dischtime, admittime, DAY) AS INT64) AS los_days
  FROM
    quintiles
)
SELECT
  risk_quintile,
  COUNT(*) AS N,
  ROUND(SUM(died_within_90d) / COUNT(*), 4) AS mortality_90d_rate,
  ROUND(SUM(has_major_complication) / COUNT(*), 4) AS major_complication_rate,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_90d_survivors
FROM
  outcomes
WHERE
  -- For median LOS, only include survivors
  died_within_90d = 0
GROUP BY
  risk_quintile
ORDER BY
  risk_quintile;