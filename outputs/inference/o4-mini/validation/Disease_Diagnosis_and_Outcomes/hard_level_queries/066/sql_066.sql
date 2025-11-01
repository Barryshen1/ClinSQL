WITH
-- 1. Define the index admission per subject for male 81–91
base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    -- placeholder risk_score (replace with your actual computation or source)
    0 AS risk_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),
-- 2. Mark pulmonary embolism admissions
pe_cohort AS (
  SELECT
    b.*
  FROM
    base AS b
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON b.subject_id = d.subject_id
      AND b.hadm_id = d.hadm_id
      AND d.icd_version = 10
      AND d.icd_code LIKE 'I26%'  -- Pulmonary embolism ICD-10 codes
),
-- 3. Get first admission per subject in each set
pe_first AS (
  SELECT
    *,
    ROW_NUMBER() OVER(PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    pe_cohort
),
all_first AS (
  SELECT
    *,
    ROW_NUMBER() OVER(PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM
    base
),
pe_idx AS (
  SELECT * EXCEPT(rn)
  FROM pe_first
  WHERE rn = 1
),
all_idx AS (
  SELECT * EXCEPT(rn)
  FROM all_first
  WHERE rn = 1
),
-- 4. Compute 75th percentile risk_score in PE cohort
pe_percentiles AS (
  SELECT
    APPROX_QUANTILES(risk_score, 100)[OFFSET(75)] AS p75_risk
  FROM
    pe_idx
),
-- 5. Label high-risk
pe_high AS (
  SELECT
    p.*,
    pp.p75_risk
  FROM
    pe_idx AS p
    CROSS JOIN pe_percentiles AS pp
  WHERE
    p.risk_score > pp.p75_risk
),
-- 6. Define outcomes flags
with_flags AS (
  SELECT
    ph.subject_id,
    ph.hadm_id,
    ph.risk_score,
    ph.p75_risk,
    IF(
      ph.deathtime IS NOT NULL
      AND DATE_DIFF(ph.deathtime, ph.dischtime, DAY) <= 90,
      1,
      0
    ) AS died90,
    DATE_DIFF(ph.dischtime, ph.admittime, DAY) AS los,
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d2
        WHERE d2.subject_id = ph.subject_id
          AND d2.hadm_id = ph.hadm_id
          AND d2.icd_version = 10
          AND d2.icd_code LIKE 'N17%'
      ),
      1,
      0
    ) AS aki_flag,
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d3
        WHERE d3.subject_id = ph.subject_id
          AND d3.hadm_id = ph.hadm_id
          AND d3.icd_version = 10
          AND d3.icd_code = 'J80'
      ),
      1,
      0
    ) AS ards_flag
  FROM
    pe_high AS ph
),
-- 7. Aggregate for the high-risk PE subcohort
pe_stats AS (
  SELECT
    'High-risk PE (Top 25%)' AS group_name,
    COUNT(*) AS n,
    ROUND(AVG(risk_score), 2) AS mean_risk_score,
    ROUND(100 * AVG(died90), 1) AS pct_90d_mortality,
    ROUND(100 * AVG(aki_flag), 1) AS pct_AKI,
    ROUND(100 * AVG(ards_flag), 1) AS pct_ARDS,
    ROUND(
      AVG(CASE WHEN died90 = 0 THEN los ELSE NULL END),
      1
    ) AS mean_los_survivors,
    MAX(p75_risk) AS matched_profile_risk_percentile_75_value
  FROM
    with_flags
),
-- 8. Repeat flags & stats for all inpatients (male 81–91)
all_flags AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.risk_score,
    IF(
      a.deathtime IS NOT NULL
      AND DATE_DIFF(a.deathtime, a.dischtime, DAY) <= 90,
      1,
      0
    ) AS died90,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
        WHERE d.subject_id = a.subject_id
          AND d.hadm_id = a.hadm_id
          AND d.icd_version = 10
          AND d.icd_code LIKE 'N17%'
      ),
      1,
      0
    ) AS aki_flag,
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
        WHERE d.subject_id = a.subject_id
          AND d.hadm_id = a.hadm_id
          AND d.icd_version = 10
          AND d.icd_code = 'J80'
      ),
      1,
      0
    ) AS ards_flag
  FROM
    all_idx AS a
),
all_stats AS (
  SELECT
    'All male 81-91 inpatients' AS group_name,
    COUNT(*) AS n,
    ROUND(AVG(risk_score), 2) AS mean_risk_score,
    ROUND(100 * AVG(died90), 1) AS pct_90d_mortality,
    ROUND(100 * AVG(aki_flag), 1) AS pct_AKI,
    ROUND(100 * AVG(ards_flag), 1) AS pct_ARDS,
    ROUND(
      AVG(CASE WHEN died90 = 0 THEN los ELSE NULL END),
      1
    ) AS mean_los_survivors,
    NULL AS matched_profile_risk_percentile_75_value
  FROM
    all_flags
)
-- 9. Final union
SELECT * FROM pe_stats
UNION ALL
SELECT * FROM all_stats;