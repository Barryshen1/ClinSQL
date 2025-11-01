WITH 
eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 40 AND 50
),
hemorrhagic_stroke AS (
  SELECT DISTINCT d.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE (d.icd_version = 9 AND d.icd_code BETWEEN '430' AND '432') 
     OR (d.icd_version = 10 AND d.icd_code BETWEEN 'I60' AND 'I62')
),
icu_stays AS (
  SELECT i.subject_id, i.stay_id, i.intime, 
         TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) AS icu_los_hours,
         COUNT(pe.itemid) AS num_diagnostic_procedures
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON i.stay_id = pe.stay_id 
    AND pe.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY i.subject_id, i.stay_id, i.intime, i.outtime
),
mortality AS (
  SELECT a.subject_id, a.hadm_id, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
combined_data AS (
  SELECT 
    ep.subject_id,
    icu.stay_id,
    icu.num_diagnostic_procedures,
    icu.icu_los_hours,
    m.hospital_expire_flag,
    CASE WHEN hs.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_hemorrhagic_stroke
  FROM eligible_patients ep
  JOIN icu_stays icu ON ep.subject_id = icu.subject_id
  JOIN mortality m ON ep.subject_id = m.subject_id
  LEFT JOIN hemorrhagic_stroke hs ON ep.subject_id = hs.subject_id
)
SELECT 
  has_hemorrhagic_stroke,
  APPROX_QUANTILES(num_diagnostic_procedures, 100)[OFFSET(90)] AS percentile_90_diagnostic_procedures,
  APPROX_QUANTILES(icu_los_hours, 100)[OFFSET(90)] AS percentile_90_icu_los_hours,
  AVG(hospital_expire_flag) AS in_hospital_mortality
FROM combined_data
GROUP BY has_hemorrhagic_stroke;