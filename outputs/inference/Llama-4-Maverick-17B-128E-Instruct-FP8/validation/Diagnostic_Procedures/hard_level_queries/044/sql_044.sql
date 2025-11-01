WITH 
patient_cohort AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, icu.stay_id, a.admittime, a.dischtime, a.hospital_expire_flag,
         icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 82 AND 92
),
procedure_counts AS (
  SELECT pc.subject_id, pc.stay_id, COUNT(pe.itemid) AS procedure_count
  FROM patient_cohort pc
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON pc.stay_id = pe.stay_id
  WHERE pe.starttime >= pc.intime AND pe.starttime < (pc.intime + INTERVAL 1 DAY)
  GROUP BY pc.subject_id, pc.stay_id
),
hospital_los AS (
  SELECT pc.subject_id, pc.hadm_id, pc.stay_id, 
         DATETIME_DIFF(pc.dischtime, pc.admittime, DAY) AS hospital_los,
         pc.hospital_expire_flag
  FROM patient_cohort pc
),
merged_data AS (
  SELECT hl.subject_id, hl.stay_id, COALESCE(pc.procedure_count, 0) AS procedure_count,
         hl.hospital_los, hl.hospital_expire_flag
  FROM hospital_los hl
  LEFT JOIN procedure_counts pc ON hl.stay_id = pc.stay_id
),
quintile_stratification AS (
  SELECT subject_id, stay_id, procedure_count, hospital_los, hospital_expire_flag,
         NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM merged_data
)
SELECT 
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(hospital_los) AS mean_hospital_los,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percentage
FROM quintile_stratification
GROUP BY quintile
ORDER BY quintile;