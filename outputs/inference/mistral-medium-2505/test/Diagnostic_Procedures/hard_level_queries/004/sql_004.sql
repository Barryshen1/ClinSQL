WITH
-- Define age range (50-60) based on anchor_age and anchor_year
patient_age AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    anchor_age + (EXTRACT(YEAR FROM CURRENT_DATE()) - anchor_year) AS current_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),

-- Identify female patients aged 50-60 with intracranial hemorrhage
ich_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.current_age,
    a.hadm_id
  FROM patient_age p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.current_age BETWEEN 50 AND 60
    AND (
      -- ICD-9 codes for intracranial hemorrhage
      (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '432')
      OR
      -- ICD-10 codes for intracranial hemorrhage
      (d.icd_version = 10 AND d.icd_code LIKE 'I6%')
    )
),

-- Get first ICU stay for each patient
first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS stay_rank
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN ich_patients ip ON i.subject_id = ip.subject_id AND i.hadm_id = ip.hadm_id
),

-- Filter to only first ICU stay per patient
ich_icu_stays AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime,
    los
  FROM first_icu_stays
  WHERE stay_rank = 1
),

-- Count procedures in first 72 hours of ICU stay
procedure_counts AS (
  SELECT
    p.stay_id,
    COUNT(DISTINCT p.itemid) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN ich_icu_stays i ON p.stay_id = i.stay_id
  WHERE p.starttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY p.stay_id
),

-- Calculate percentiles for procedure burden
procedure_percentiles AS (
  SELECT
    PERCENTILE_CONT(procedure_count, 0.25) OVER() AS percentile_25,
    PERCENTILE_CONT(procedure_count, 0.5) OVER() AS percentile_50,
    PERCENTILE_CONT(procedure_count, 0.9) OVER() AS percentile_90
  FROM procedure_counts
  LIMIT 1
),

-- General ICU population (excluding ICH patients)
general_icu_population AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  WHERE i.subject_id NOT IN (SELECT subject_id FROM ich_patients)
),

-- Compare ICU LOS and mortality
comparison_stats AS (
  SELECT
    'ICH Patients' AS cohort,
    AVG(los) AS avg_icu_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS mortality_rate
  FROM ich_icu_stays i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id

  UNION ALL

  SELECT
    'General ICU Population' AS cohort,
    AVG(los) AS avg_icu_los,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS mortality_rate
  FROM general_icu_population g
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON g.subject_id = a.subject_id AND g.hadm_id = a.hadm_id
)

-- Final results for procedure burden
SELECT
  'Procedure Burden Percentiles' AS metric,
  percentile_25,
  percentile_50,
  percentile_90
FROM procedure_percentiles

UNION ALL

-- Final results for cohort comparison
SELECT
  'ICU LOS and Mortality Comparison' AS metric,
  NULL AS percentile_25,
  NULL AS percentile_50,
  NULL AS percentile_90
FROM comparison_stats
WHERE cohort = 'ICH Patients'

UNION ALL

SELECT
  'General ICU Population' AS metric,
  NULL AS percentile_25,
  NULL AS percentile_50,
  NULL AS percentile_90
FROM comparison_stats
WHERE cohort = 'General ICU Population'
ORDER BY metric;