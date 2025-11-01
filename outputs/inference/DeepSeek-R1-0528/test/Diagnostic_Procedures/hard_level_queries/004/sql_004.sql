WITH base_cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id,
    ie.intime, 
    ie.los AS icu_los,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    adm.admittime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.hadm_id = adm.hadm_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 50 AND 60
),

ich_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('430', '431', '4320', '4321', '4329')) OR
    (icd_version = 10 AND icd_code IN ('I60', 'I61', 'I62'))
),

cohort_with_ich AS (
  SELECT 
    bc.*,
    CASE WHEN ich.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS ich_flag
  FROM base_cohort bc
  LEFT JOIN ich_diagnoses ich
    ON bc.hadm_id = ich.hadm_id
),

procedure_counts AS (
  SELECT 
    c.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM cohort_with_ich c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime < DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
  WHERE c.ich_flag = 1
  GROUP BY c.stay_id
),

procedure_burden_summary AS (
  SELECT 
    'ICH' AS group_name,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS procedure_burden_25,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS procedure_burden_50,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(90)] AS procedure_burden_90
  FROM procedure_counts
),

comparison_summary AS (
  SELECT 
    CASE WHEN ich_flag = 1 THEN 'ICH' ELSE 'non-ICH' END AS group_name,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    COUNT(stay_id) AS total_icu_stays,
    APPROX_QUANTILES(icu_los, 100)[OFFSET(25)] AS los_25,
    APPROX_QUANTILES(icu_los, 100)[OFFSET(50)] AS los_50,
    APPROX_QUANTILES(icu_los, 100)[OFFSET(90)] AS los_90,
    COUNT(DISTINCT CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) AS mortality_count
  FROM cohort_with_ich
  GROUP BY ich_flag
)

-- Part 1: Procedure burden for ICH group
SELECT 
  group_name,
  procedure_burden_25,
  procedure_burden_50,
  procedure_burden_90,
  NULL AS los_25,
  NULL AS los_50,
  NULL AS los_90,
  NULL AS total_admissions,
  NULL AS total_icu_stays,
  NULL AS mortality_count,
  NULL AS mortality_percentage
FROM procedure_burden_summary

UNION ALL

-- Part 2: Comparison (LOS and mortality for ICH vs. non-ICH)
SELECT 
  group_name,
  NULL, NULL, NULL,  -- Procedure burden columns
  los_25,
  los_50,
  los_90,
  total_admissions,
  total_icu_stays,
  mortality_count,
  ROUND(mortality_count / total_admissions * 100, 2) AS mortality_percentage
FROM comparison_summary;