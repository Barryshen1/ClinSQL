WITH eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, icu.hadm_id, icu.stay_id, icu.intime, 
         a.hospital_expire_flag, icu.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON p.subject_id = icu.subject_id
  JOIN (
    SELECT subject_id, hadm_id, MIN(intime) AS first_icu_intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY subject_id, hadm_id
  ) first_icu ON icu.subject_id = first_icu.subject_id AND icu.hadm_id = first_icu.hadm_id AND icu.intime = first_icu.first_icu_intime
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON icu.hadm_id = a.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 37 AND 47
),
procedures AS (
  SELECT ep.subject_id, ep.stay_id, COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON ep.stay_id = pe.stay_id
  WHERE pe.starttime <= TIMESTAMP_ADD(ep.intime, INTERVAL 48 HOUR)
  GROUP BY ep.subject_id, ep.stay_id
),
patient_data AS (
  SELECT ep.subject_id, ep.stay_id, ep.hospital_expire_flag, 
         TIMESTAMP_DIFF(ep.outtime, ep.intime, HOUR) / 24.0 AS icu_los,
         COALESCE(p.procedure_count, 0) AS procedure_count
  FROM eligible_patients ep
  LEFT JOIN procedures p ON ep.stay_id = p.stay_id
),
quintiles AS (
  SELECT subject_id, stay_id, hospital_expire_flag, icu_los, procedure_count,
         NTILE(5) OVER (ORDER BY procedure_count) AS quintile
  FROM patient_data
)
SELECT 
  quintile,
  AVG(procedure_count) AS mean_procedure_count,
  AVG(icu_los) AS mean_icu_los,
  AVG(hospital_expire_flag) AS hospital_mortality
FROM quintiles
GROUP BY quintile
ORDER BY quintile;