WITH
-- Define sepsis ICD codes (common sepsis codes)
sepsis_icd_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%sepsis%'
     OR icd_code IN ('995.91', '995.92', 'A41.9', 'A40', 'A41.0', 'A41.1', 'A41.2', 'A41.3', 'A41.4', 'A41.5', 'A41.8', 'A41.9')
),

-- Get female patients aged 53-63
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 53 AND 63
),

-- Get ICU stays with sepsis
icu_sepsis_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  JOIN female_patients fp
    ON s.subject_id = fp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON s.hadm_id = d.hadm_id
  JOIN sepsis_icd_codes sc
    ON d.icd_code = sc.icd_code
),

-- Get ICU stays without sepsis (age-matched)
icu_non_sepsis_stays AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime,
    TIMESTAMP_DIFF(s.outtime, s.intime, HOUR) AS icu_los_hours,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.hadm_id = a.hadm_id
  JOIN female_patients fp
    ON s.subject_id = fp.subject_id
  WHERE s.subject_id NOT IN (
    SELECT subject_id FROM icu_sepsis_stays
  )
),

-- Count procedures in first 24 hours for sepsis patients
sepsis_procedures AS (
  SELECT
    p.stay_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN icu_sepsis_stays s
    ON p.stay_id = s.stay_id
  WHERE TIMESTAMP_DIFF(p.starttime, s.intime, HOUR) <= 24
  GROUP BY p.stay_id
),

-- Count procedures in first 24 hours for non-sepsis patients
non_sepsis_procedures AS (
  SELECT
    p.stay_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN icu_non_sepsis_stays s
    ON p.stay_id = s.stay_id
  WHERE TIMESTAMP_DIFF(p.starttime, s.intime, HOUR) <= 24
  GROUP BY p.stay_id
),

-- Aggregate results for sepsis patients
sepsis_agg AS (
  SELECT
    PERCENTILE_CONT(procedure_count, 0.75) AS percentile_75,
    PERCENTILE_CONT(procedure_count, 0.90) AS percentile_90,
    AVG(icu_los_hours) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate
  FROM icu_sepsis_stays s
  JOIN sepsis_procedures p
    ON s.stay_id = p.stay_id
),

-- Aggregate results for non-sepsis patients
non_sepsis_agg AS (
  SELECT
    PERCENTILE_CONT(procedure_count, 0.75) AS percentile_75,
    PERCENTILE_CONT(procedure_count, 0.90) AS percentile_90,
    AVG(icu_los_hours) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate
  FROM icu_non_sepsis_stays s
  JOIN non_sepsis_procedures p
    ON s.stay_id = p.stay_id
)

-- Final comparison
SELECT
  'Sepsis Patients' AS group_name,
  percentile_75,
  percentile_90,
  avg_icu_los,
  mortality_rate
FROM sepsis_agg

UNION ALL

SELECT
  'Non-Sepsis Patients (Age-Matched)' AS group_name,
  percentile_75,
  percentile_90,
  avg_icu_los,
  mortality_rate
FROM non_sepsis_agg
ORDER BY group_name;