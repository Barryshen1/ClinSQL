WITH eligible_patients AS (
  SELECT subject_id, anchor_age, gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE anchor_age BETWEEN 50 AND 60
    AND gender = 'F'
),
ich_icd_codes AS (
  SELECT 'I60' AS icd_code UNION ALL
  SELECT 'I61' UNION ALL
  SELECT 'I62' UNION ALL
  SELECT 'I63' UNION ALL
  SELECT 'I64' UNION ALL
  SELECT 'I65' UNION ALL
  SELECT 'I66' UNION ALL
  SELECT 'I67' UNION ALL
  SELECT 'I68' UNION ALL
  SELECT 'I69' UNION ALL
  SELECT 'I70' UNION ALL
  SELECT 'I71' UNION ALL
  SELECT 'I72' UNION ALL
  SELECT 'I73' UNION ALL
  SELECT 'I74' UNION ALL
  SELECT 'I75' UNION ALL
  SELECT 'I76' UNION ALL
  SELECT 'I77' UNION ALL
  SELECT 'I78' UNION ALL
  SELECT 'I79' UNION ALL
  SELECT 'I80' UNION ALL
  SELECT 'I81' UNION ALL
  SELECT 'I82' UNION ALL
  SELECT 'I83' UNION ALL
  SELECT 'I84' UNION ALL
  SELECT 'I85' UNION ALL
  SELECT 'I86' UNION ALL
  SELECT 'I87' UNION ALL
  SELECT 'I88' UNION ALL
  SELECT 'I89' UNION ALL
  SELECT 'I90' UNION ALL
  SELECT 'I91' UNION ALL
  SELECT 'I92' UNION ALL
  SELECT 'I93' UNION ALL
  SELECT 'I94' UNION ALL
  SELECT 'I95' UNION ALL
  SELECT 'I96' UNION ALL
  SELECT 'I97' UNION ALL
  SELECT 'I98' UNION ALL
  SELECT 'I99'
),
ich_diagnoses AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN ich_icd_codes c ON d.icd_code = c.icd_code
  WHERE d.icd_version = 10  -- ICD-10
),
first_icu_stays_ich AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime,
         ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_patients ep ON i.subject_id = ep.subject_id
  INNER JOIN ich_diagnoses ich ON i.subject_id = ich.subject_id AND i.hadm_id = ich.hadm_id
),
ich_icu_first_stay AS (
  SELECT subject_id, hadm_id, stay_id, intime
  FROM first_icu_stays_ich
  WHERE rn = 1
),
admissions_ich AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN ich_icu_first_stay i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
),
procedure_events_ich AS (
  SELECT p.subject_id, p.hadm_id, p.stay_id, COUNT(*) AS procedure_burden
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  INNER JOIN ich_icu_first_stay i 
    ON p.subject_id = i.subject_id AND p.hadm_id = i.hadm_id AND p.stay_id = i.stay_id
  WHERE p.starttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY p.subject_id, p.hadm_id, p.stay_id
),
ich_cohort_data AS (
  SELECT a.subject_id, a.hadm_id, a.los_days, a.hospital_expire_flag, COALESCE(p.procedure_burden, 0) AS procedure_burden
  FROM admissions_ich a
  LEFT JOIN procedure_events_ich p 
    ON a.subject_id = p.subject_id AND a.hadm_id = p.hadm_id
),
-- Now aggregate for ICH cohort
ich_stats AS (
  SELECT 
    APPROX_QUANTILES(procedure_burden, 100)[OFFSET(25)] AS procedure_burden_25th,
    APPROX_QUANTILES(procedure_burden, 100)[OFFSET(50)] AS procedure_burden_50th,
    APPROX_QUANTILES(procedure_burden, 100)[OFFSET(90)] AS procedure_burden_90th,
    MAX(procedure_burden) AS procedure_burden_max,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_median,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM ich_cohort_data
),
-- For general ICU cohort (without ICH)
non_ich_patients AS (
  SELECT ep.subject_id
  FROM eligible_patients ep
  LEFT JOIN ich_diagnoses ich ON ep.subject_id = ich.subject_id
  WHERE ich.subject_id IS NULL
),
first_icu_stays_general AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime,
         ROW_NUMBER() OVER (PARTITION BY i.subject_id, i.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN non_ich_patients n ON i.subject_id = n.subject_id
),
general_icu_first_stay AS (
  SELECT subject_id, hadm_id, stay_id, intime
  FROM first_icu_stays_general
  WHERE rn = 1
),
admissions_general AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN general_icu_first_stay g ON a.subject_id = g.subject_id AND a.hadm_id = g.hadm_id
),
general_icu_cohort_data AS (
  SELECT subject_id, hadm_id, los_days, hospital_expire_flag
  FROM admissions_general
),
general_icu_stats AS (
  SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_median,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM general_icu_cohort_data
)
-- Combine results
SELECT 
  'ICH' AS cohort,
  procedure_burden_25th,
  procedure_burden_50th,
  procedure_burden_90th,
  procedure_burden_max,
  los_median,
  mortality_rate
FROM ich_stats

UNION ALL

SELECT 
  'general ICU' AS cohort,
  NULL AS procedure_burden_25th,
  NULL AS procedure_burden_50th,
  NULL AS procedure_burden_90th,
  NULL AS procedure_burden_max,
  los_median,
  mortality_rate
FROM general_icu_stats;