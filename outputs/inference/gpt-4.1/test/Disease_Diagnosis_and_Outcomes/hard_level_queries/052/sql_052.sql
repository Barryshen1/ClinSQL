WITH
-- 1. Identify all female inpatients aged 75–85
female_75_85 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
),

-- 2. Identify COPD exacerbation admissions
copd_exacerbation_admissions AS (
  SELECT DISTINCT
    f.subject_id,
    f.hadm_id,
    f.anchor_age,
    f.gender,
    f.admittime,
    f.dischtime,
    f.dod
  FROM
    female_75_85 f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    f.hadm_id = d.hadm_id
  WHERE
    (
      -- ICD-10 J44.1, J44.0
      (d.icd_version = 10 AND d.icd_code IN ('J441', 'J440'))
      -- ICD-9 491.21
      OR (d.icd_version = 9 AND d.icd_code IN ('49121'))
    )
),

-- 3. Calculate risk score (proxy: number of unique ICD codes per admission)
risk_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.admittime,
    c.dischtime,
    c.dod,
    COUNT(DISTINCT d.icd_code) AS risk_score
  FROM
    copd_exacerbation_admissions c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id, c.anchor_age, c.gender, c.admittime, c.dischtime, c.dod
),

-- 4. Assign quartiles by risk score
quartiled AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY risk_score) AS risk_quartile
  FROM
    risk_scores
),

-- 5. Flag 90-day mortality
mortality_flagged AS (
  SELECT
    *,
    CASE
      WHEN dod IS NOT NULL AND DATETIME(dod) <= DATETIME(admittime) + INTERVAL 90 DAY THEN 1
      ELSE 0
    END AS died_within_90d,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM
    quartiled
),

-- 6. Flag major complications (sepsis, ARF, MI, stroke, etc.)
major_complication_icds AS (
  -- List of major complication ICD codes (ICD-10 and ICD-9)
  SELECT 'A419' AS icd_code, 10 AS icd_version UNION ALL -- Sepsis
  SELECT 'R652', 10 UNION ALL -- Severe sepsis
  SELECT 'N179', 10 UNION ALL -- Acute renal failure
  SELECT 'I219', 10 UNION ALL -- Acute MI
  SELECT 'I639', 10 UNION ALL -- Stroke
  SELECT '99591', 9 UNION ALL -- Sepsis
  SELECT '99592', 9 UNION ALL -- Severe sepsis
  SELECT '5849', 9 UNION ALL -- Acute renal failure
  SELECT '41071', 9 UNION ALL -- Acute MI
  SELECT '43491', 9 -- Stroke
),

complication_flagged AS (
  SELECT
    m.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        JOIN major_complication_icds mc
        ON d.icd_code = mc.icd_code AND d.icd_version = mc.icd_version
        WHERE d.hadm_id = m.hadm_id
      ) THEN 1
      ELSE 0
    END AS major_complication
  FROM
    mortality_flagged m
),

-- 7. Aggregate per quartile
quartile_summary AS (
  SELECT
    risk_quartile,
    COUNT(*) AS n_admissions,
    SUM(died_within_90d) / COUNT(*) AS mortality_90d_rate,
    SUM(major_complication) / COUNT(*) AS major_complication_rate,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_survivor_los
  FROM
    complication_flagged
  WHERE
    died_within_90d = 0 -- For median survivor LOS
  GROUP BY
    risk_quartile
),

-- 8. Broader 75–85 female 90-day mortality
broader_90d_mortality AS (
  SELECT
    COUNT(*) AS n_admissions,
    SUM(
      CASE
        WHEN dod IS NOT NULL AND DATETIME(dod) <= DATETIME(admittime) + INTERVAL 90 DAY THEN 1
        ELSE 0
      END
    ) / COUNT(*) AS mortality_90d_rate
  FROM
    female_75_85
)

-- Final output
SELECT
  'COPD_exacerbation_quartile' AS group_type,
  risk_quartile,
  n_admissions,
  ROUND(mortality_90d_rate * 100, 2) AS mortality_90d_percent,
  ROUND(major_complication_rate * 100, 2) AS major_complication_percent,
  median_survivor_los
FROM
  quartile_summary

UNION ALL

SELECT
  'female_75_85_all' AS group_type,
  NULL AS risk_quartile,
  n_admissions,
  ROUND(mortality_90d_rate * 100, 2) AS mortality_90d_percent,
  NULL AS major_complication_percent,
  NULL AS median_survivor_los
FROM
  broader_90d_mortality;