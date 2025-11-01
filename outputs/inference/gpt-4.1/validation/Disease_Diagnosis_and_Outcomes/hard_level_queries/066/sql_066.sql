WITH
-- 1. All male inpatients age 81-91
base_inpatients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
),

-- 2. Identify PE admissions
pe_admissions AS (
  SELECT DISTINCT
    b.subject_id,
    b.hadm_id,
    b.anchor_age,
    b.gender,
    b.admittime,
    b.dischtime,
    b.deathtime,
    b.hospital_expire_flag
  FROM
    base_inpatients b
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON b.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    (
      (d.icd_version = 9 AND d.icd_code LIKE '4151%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I26%')
      OR LOWER(dd.long_title) LIKE '%pulmonary embolism%'
    )
),

-- 3. Comorbidity risk score (Elixhauser count per admission)
elixhauser_icd_codes AS (
  -- List of ICD codes for Elixhauser comorbidities (simplified for demo)
  SELECT '250' AS icd_code_prefix, 9 AS icd_version UNION ALL -- Diabetes
  SELECT '401', 9 UNION ALL -- Hypertension
  SELECT '428', 9 UNION ALL -- CHF
  SELECT '585', 9 UNION ALL -- Renal failure
  SELECT '518', 9 UNION ALL -- COPD
  SELECT 'I10', 10 UNION ALL -- Hypertension
  SELECT 'E11', 10 UNION ALL -- Diabetes
  SELECT 'I50', 10 UNION ALL -- CHF
  SELECT 'N18', 10 UNION ALL -- Renal failure
  SELECT 'J44', 10 -- COPD
),

comorbidity_scores AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    COUNT(DISTINCT CASE
      WHEN d.icd_version = e.icd_version AND d.icd_code LIKE CONCAT(e.icd_code_prefix, '%')
      THEN e.icd_code_prefix
      ELSE NULL
    END) AS risk_score
  FROM
    base_inpatients b
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON b.hadm_id = d.hadm_id
    LEFT JOIN elixhauser_icd_codes e ON d.icd_version = e.icd_version AND d.icd_code LIKE CONCAT(e.icd_code_prefix, '%')
  GROUP BY
    b.subject_id, b.hadm_id
),

-- 4. 75th percentile risk score among all inpatients
risk_score_percentiles AS (
  SELECT
    APPROX_QUANTILES(risk_score, 4)[OFFSET(3)] AS risk_score_75th
  FROM comorbidity_scores
),

-- 5. Target cohort: PE + risk_score > 75th percentile
target_cohort AS (
  SELECT
    pe.*,
    cs.risk_score
  FROM
    pe_admissions pe
    JOIN comorbidity_scores cs ON pe.hadm_id = cs.hadm_id
    CROSS JOIN risk_score_percentiles r
  WHERE
    cs.risk_score > r.risk_score_75th
),

-- 6. 90-day mortality
target_mortality AS (
  SELECT
    tc.*,
    CASE
      WHEN tc.deathtime IS NOT NULL AND DATETIME_DIFF(tc.deathtime, tc.admittime, DAY) <= 90 THEN 1
      WHEN tc.hospital_expire_flag = 1 AND DATETIME_DIFF(tc.dischtime, tc.admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS died_90d,
    DATETIME_DIFF(tc.dischtime, tc.admittime, DAY) AS los_days
  FROM target_cohort tc
),

-- 7. AKI/ARDS rates in target cohort
target_aki_ards AS (
  SELECT
    t.hadm_id,
    MAX(CASE
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '584%') OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
      THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE
      WHEN (d.icd_version = 9 AND d.icd_code = '51882') OR (d.icd_version = 10 AND d.icd_code = 'J80')
      THEN 1 ELSE 0 END) AS has_ards
  FROM
    target_mortality t
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON t.hadm_id = d.hadm_id
  GROUP BY t.hadm_id
),

-- 8. Survivors in target cohort
target_survivors AS (
  SELECT
    tm.*,
    ta.has_aki,
    ta.has_ards
  FROM
    target_mortality tm
    LEFT JOIN target_aki_ards ta ON tm.hadm_id = ta.hadm_id
  WHERE
    tm.died_90d = 0
),

-- 9. All inpatients (age/gender matched) for comparison
all_mortality AS (
  SELECT
    b.*,
    cs.risk_score,
    CASE
      WHEN b.deathtime IS NOT NULL AND DATETIME_DIFF(b.deathtime, b.admittime, DAY) <= 90 THEN 1
      WHEN b.hospital_expire_flag = 1 AND DATETIME_DIFF(b.dischtime, b.admittime, DAY) <= 90 THEN 1
      ELSE 0
    END AS died_90d,
    DATETIME_DIFF(b.dischtime, b.admittime, DAY) AS los_days
  FROM base_inpatients b
  LEFT JOIN comorbidity_scores cs ON b.hadm_id = cs.hadm_id
),

all_aki_ards AS (
  SELECT
    a.hadm_id,
    MAX(CASE
      WHEN (d.icd_version = 9 AND d.icd_code LIKE '584%') OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
      THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE
      WHEN (d.icd_version = 9 AND d.icd_code = '51882') OR (d.icd_version = 10 AND d.icd_code = 'J80')
      THEN 1 ELSE 0 END) AS has_ards
  FROM
    all_mortality a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  GROUP BY a.hadm_id
),

all_survivors AS (
  SELECT
    am.*,
    aa.has_aki,
    aa.has_ards
  FROM
    all_mortality am
    LEFT JOIN all_aki_ards aa ON am.hadm_id = aa.hadm_id
  WHERE
    am.died_90d = 0
),

-- 10. Risk percentile for matched profile
target_risk_percentile AS (
  SELECT
    AVG(CASE WHEN am.risk_score < tr.risk_score THEN 1 ELSE 0 END) AS percentile
  FROM
    target_cohort tr
    CROSS JOIN all_mortality am
  WHERE am.risk_score IS NOT NULL
)

-- Final output
SELECT
  -- Target cohort summary
  'Target cohort (PE, high risk)' AS cohort_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(risk_score),2) AS mean_risk_score,
  ROUND(SUM(died_90d)/COUNT(*),3) AS mortality_90d,
  ROUND(SUM(has_aki)/COUNT(*),3) AS aki_rate,
  ROUND(SUM(has_ards)/COUNT(*),3) AS ards_rate,
  ROUND(AVG(los_days),1) AS mean_los_survivors,
  (SELECT ROUND(percentile*100,1) FROM target_risk_percentile) AS matched_profile_risk_percentile
FROM target_survivors

UNION ALL

SELECT
  'All inpatients (age/gender matched)' AS cohort_group,
  COUNT(*) AS n_admissions,
  ROUND(AVG(risk_score),2) AS mean_risk_score,
  ROUND(SUM(died_90d)/COUNT(*),3) AS mortality_90d,
  ROUND(SUM(has_aki)/COUNT(*),3) AS aki_rate,
  ROUND(SUM(has_ards)/COUNT(*),3) AS ards_rate,
  ROUND(AVG(los_days),1) AS mean_los_survivors,
  NULL AS matched_profile_risk_percentile
FROM all_survivors
;