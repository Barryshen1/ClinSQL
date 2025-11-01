WITH asthma_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE icd_version = 10 AND icd_code LIKE 'J45%'  
),
age_filtered_patients AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 77 AND 87
  AND a.hadm_id IN (SELECT hadm_id FROM asthma_patients)
),
icu_stays AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, 
         DATETIME_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours
  FROM `physionet-data.mimiciv_3_1_icu`.icustays i
  INNER JOIN age_filtered_patients afp ON i.hadm_id = afp.hadm_id
),
procedures AS (
  SELECT pe.stay_id, COUNT(*) AS procedure_count
  FROM `physionet-data.mimiciv_3_1_icu`.procedureevents pe
  INNER JOIN icu_stays i ON pe.stay_id = i.stay_id
  WHERE pe.starttime <= DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY pe.stay_id
),
icu_data AS (
  SELECT i.stay_id, i.intime, i.outtime, afp.hospital_expire_flag, 
         DATETIME_DIFF(afp.dischtime, afp.admittime, DAY) AS hospital_los_days
  FROM icu_stays i
  INNER JOIN age_filtered_patients afp ON i.hadm_id = afp.hadm_id
),
combined_data AS (
  SELECT id.stay_id, id.hospital_expire_flag, id.hospital_los_days, 
         COALESCE(p.procedure_count, 0) AS procedure_count
  FROM icu_data id
  LEFT JOIN procedures p ON id.stay_id = p.stay_id
),
stratified_data AS (
  SELECT procedure_count, hospital_los_days, hospital_expire_flag,
         NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM combined_data
)
SELECT quartile,
       COUNT(*) AS count,
       AVG(procedure_count) AS mean_procedure_count,
       AVG(hospital_los_days) AS mean_hospital_los_days,
       AVG(hospital_expire_flag) * 100 AS hospital_mortality_percent
FROM stratified_data
GROUP BY quartile
ORDER BY quartile;