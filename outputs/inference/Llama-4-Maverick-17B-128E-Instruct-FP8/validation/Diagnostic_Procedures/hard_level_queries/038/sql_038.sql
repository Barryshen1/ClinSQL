WITH 
-- Step 1: Identify patients with intracranial hemorrhage and their first ICU stay
ich_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_year, p.anchor_age, 
         i.hadm_id, i.stay_id, i.intime, 
         a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
    ON p.subject_id = diag.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag 
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  JOIN (
    SELECT subject_id, hadm_id, stay_id, intime, 
           ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i 
    ON p.subject_id = i.subject_id AND diag.hadm_id = i.hadm_id AND i.rn = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 60 AND 70
    AND d_diag.long_title LIKE '%Intracranial hemorrhage%'
),
-- Step 2: Calculate procedure burden in the first 72h for ICH patients
ich_procedure_burden AS (
  SELECT i.subject_id, i.stay_id, COUNT(pe.itemid) AS procedure_count
  FROM ich_patients i
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON i.stay_id = pe.stay_id
  WHERE pe.starttime <= TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.subject_id, i.stay_id
),
-- Step 3: Calculate mean ICU LOS and hospital mortality for ICH patients
ich_outcomes AS (
  SELECT AVG(icu.los) AS mean_icu_los, 
         AVG(CAST(a.hospital_expire_flag AS INT64)) AS hospital_mortality
  FROM ich_patients i
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
    ON i.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
),
-- Step 4: Compare with general ICU population
general_icu_population AS (
  SELECT p.subject_id, i.stay_id, i.intime, i.los, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN (
    SELECT subject_id, hadm_id, stay_id, intime, los, 
           ROW_NUMBER() OVER (PARTITION BY subject_id, hadm_id ORDER BY intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) i 
    ON p.subject_id = i.subject_id AND i.rn = 1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 60 AND 70
),
general_procedure_burden AS (
  SELECT i.subject_id, i.stay_id, COUNT(pe.itemid) AS procedure_count
  FROM general_icu_population i
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON i.stay_id = pe.stay_id
  WHERE pe.starttime <= TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.subject_id, i.stay_id
),
general_outcomes AS (
  SELECT AVG(i.los) AS mean_icu_los, 
         AVG(CAST(i.hospital_expire_flag AS INT64)) AS hospital_mortality
  FROM general_icu_population i
)

-- Final query to get the 75th percentile of procedure burden and compare outcomes
SELECT 
  APPROX_QUANTILES(ipb.procedure_count, 100)[OFFSET(75)] AS procedure_burden_75th_percentile,
  io.mean_icu_los,
  io.hospital_mortality,
  go.mean_icu_los AS general_mean_icu_los,
  go.hospital_mortality AS general_hospital_mortality
FROM ich_procedure_burden ipb
CROSS JOIN ich_outcomes io
CROSS JOIN general_outcomes go;