WITH
-- Base population: female inpatients aged 70-80
base_population AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE WHEN a.deathtime IS NOT NULL OR p.dod IS NOT NULL THEN 1 ELSE 0 END AS died_in_hospital,
    CASE WHEN a.deathtime IS NOT NULL AND TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) <= 90 THEN 1
         WHEN p.dod IS NOT NULL AND TIMESTAMP_DIFF(p.dod, a.admittime, DAY) <= 90 THEN 1
         ELSE 0 END AS died_within_90_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- PE patients (ICD-10 codes I26.*)
pe_patients AS (
  SELECT
    b.*
  FROM
    base_population b
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON b.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I26%'
    AND d.icd_version = 10
),

-- Risk score calculation (simplified)
risk_scores AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    -- Count of comorbidities (excluding PE)
    (SELECT COUNT(DISTINCT icd_code)
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
     WHERE d.hadm_id = p.hadm_id
     AND d.icd_code NOT LIKE 'I26%'
     AND d.icd_version = 10) AS comorbidity_count,
    -- For simplicity, we'll just use comorbidity count as our risk score
    (SELECT COUNT(DISTINCT icd_code)
     FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
     WHERE d.hadm_id = p.hadm_id
     AND d.icd_code NOT LIKE 'I26%'
     AND d.icd_version = 10) AS risk_score
  FROM
    pe_patients p
),

-- Add AKI and ARDS flags
pe_with_complications AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    r.risk_score,
    b.died_within_90_days,
    b.los,
    MAX(CASE WHEN d.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN d.icd_code LIKE 'J80%' THEN 1 ELSE 0 END) AS has_ards
  FROM
    risk_scores r
  JOIN
    base_population b ON r.subject_id = b.subject_id AND r.hadm_id = b.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON r.hadm_id = d.hadm_id
  GROUP BY
    r.subject_id, r.hadm_id, r.risk_score, b.died_within_90_days, b.los
),

-- Calculate risk quintiles separately
risk_quintiles AS (
  SELECT
    subject_id,
    hadm_id,
    risk_score,
    died_within_90_days,
    los,
    has_aki,
    has_ards,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM
    pe_with_complications
),

-- General female 70-80 population for comparison
general_population AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients,
    SUM(died_within_90_days) AS deaths_within_90_days
  FROM
    base_population
),

-- Final stratified results
stratified_results AS (
  SELECT
    rq.risk_quintile,
    COUNT(DISTINCT rq.subject_id) AS patient_count,
    SUM(rq.has_aki) AS aki_count,
    SUM(rq.has_ards) AS ards_count,
    SUM(rq.died_within_90_days) AS deaths_within_90_days,
    PERCENTILE_CONT(rq.los, 0.5) OVER (PARTITION BY rq.risk_quintile) AS median_los_survivors
  FROM
    risk_quintiles rq
  GROUP BY
    rq.risk_quintile, rq.died_within_90_days, rq.los, rq.has_aki, rq.has_ards
)

-- Final output
SELECT
  sr.risk_quintile,
  sr.patient_count,
  ROUND(100 * sr.deaths_within_90_days / sr.patient_count, 2) AS pe_90day_mortality_pct,
  ROUND(100 * gp.deaths_within_90_days / gp.total_patients, 2) AS general_90day_mortality_pct,
  ROUND(100 * sr.aki_count / sr.patient_count, 2) AS aki_rate_pct,
  ROUND(100 * sr.ards_count / sr.patient_count, 2) AS ards_rate_pct,
  sr.median_los_survivors
FROM
  stratified_results sr
CROSS JOIN
  general_population gp
ORDER BY
  sr.risk_quintile;