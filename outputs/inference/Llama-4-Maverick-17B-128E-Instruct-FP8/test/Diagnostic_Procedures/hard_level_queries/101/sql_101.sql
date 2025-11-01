WITH copd_patients AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%COPD%' AND di.icd_version = 9  
),
icu_copd_patients AS (
  SELECT icu.stay_id, p.subject_id, p.anchor_age, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
  WHERE icu.hadm_id IN (SELECT hadm_id FROM copd_patients) AND p.gender = 'M' AND p.anchor_age BETWEEN 88 AND 98
),
procedures AS (
  SELECT icp.stay_id, COUNT(DISTINCT pe.itemid) as num_procedures
  FROM icu_copd_patients icp
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON icp.stay_id = pe.stay_id
  WHERE pe.starttime <= icp.intime + INTERVAL 3 DAY
  GROUP BY icp.stay_id
),
icu_los_mortality AS (
  SELECT icp.stay_id, icu.los, a.hospital_expire_flag
  FROM icu_copd_patients icp
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON icp.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON icu.hadm_id = a.hadm_id
),
age_matched_patients AS (
  SELECT icu.stay_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 88 AND 98 AND p.gender = 'M' AND icu.hadm_id NOT IN (SELECT hadm_id FROM copd_patients)
),
age_matched_procedures AS (
  SELECT amp.stay_id, COUNT(DISTINCT pe.itemid) as num_procedures
  FROM age_matched_patients amp
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe ON amp.stay_id = pe.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON pe.stay_id = icu.stay_id
  WHERE pe.starttime <= icu.intime + INTERVAL 3 DAY
  GROUP BY amp.stay_id
),
age_matched_icu_los_mortality AS (
  SELECT amp.stay_id, icu.los, a.hospital_expire_flag
  FROM age_matched_patients amp
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON amp.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON icu.hadm_id = a.hadm_id
)

SELECT 
  APPROX_QUANTILES(p.num_procedures, 100)[OFFSET(75)] AS percentile_75_procedures,
  AVG(ilm.los) AS mean_icu_los,
  AVG(ilm.hospital_expire_flag) AS in_hospital_mortality,
  APPROX_QUANTILES(amp.num_procedures, 100)[OFFSET(75)] AS percentile_75_procedures_age_matched,
  AVG(amil.los) AS mean_icu_los_age_matched,
  AVG(amil.hospital_expire_flag) AS in_hospital_mortality_age_matched
FROM procedures p
JOIN icu_los_mortality ilm ON p.stay_id = ilm.stay_id
CROSS JOIN age_matched_procedures amp
CROSS JOIN age_matched_icu_los_mortality amil;