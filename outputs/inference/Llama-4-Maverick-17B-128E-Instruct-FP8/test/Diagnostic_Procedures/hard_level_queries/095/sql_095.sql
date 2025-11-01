WITH 
-- Step 1: Filter patients and identify those with pulmonary embolism
patients_filtered AS (
  SELECT p.subject_id, p.anchor_age, p.gender, ie.hadm_id, ie.stay_id, ie.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 79 AND 89
),
pulmonary_embolism_patients AS (
  SELECT DISTINCT p.subject_id, p.hadm_id, p.stay_id, p.intime
  FROM patients_filtered p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON p.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE d_diag.long_title LIKE '%Pulmonary embolism%'
),

-- Step 2: Calculate diagnostic utilization score within the first 24 hours
diagnostic_utilization AS (
  SELECT pep.stay_id, COUNT(DISTINCT le.labevent_id) + COUNT(DISTINCT me.microevent_id) AS score
  FROM pulmonary_embolism_patients pep
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON pep.hadm_id = le.hadm_id AND le.charttime BETWEEN pep.intime AND TIMESTAMP_ADD(pep.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me ON pep.hadm_id = me.hadm_id AND me.charttime BETWEEN pep.intime AND TIMESTAMP_ADD(pep.intime, INTERVAL 24 HOUR)
  GROUP BY pep.stay_id
),

-- Step 3: Calculate ICU LOS and in-hospital mortality
icu_los_mortality AS (
  SELECT ie.stay_id, ie.los, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ie.hadm_id = a.hadm_id
)

-- Final query to get the 75th percentile of diagnostic utilization score and compare ICU LOS and mortality
SELECT 
  PERCENTILE_CONT(d.score, 0.75) AS percentile_75_diagnostic_utilization,
  AVG(il.los) AS avg_icu_los_pe,
  SUM(il.hospital_expire_flag) / COUNT(il.stay_id) AS mortality_rate_pe,
  (SELECT AVG(los) FROM icu_los_mortality) AS avg_icu_los_general,
  (SELECT SUM(hospital_expire_flag) / COUNT(stay_id) FROM icu_los_mortality) AS mortality_rate_general
FROM diagnostic_utilization d
JOIN icu_los_mortality il ON d.stay_id = il.stay_id;