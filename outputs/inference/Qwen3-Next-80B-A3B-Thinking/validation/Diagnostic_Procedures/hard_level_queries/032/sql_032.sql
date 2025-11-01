WITH first_icu AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE i.intime = (
    SELECT MIN(intime)
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i2
    WHERE i2.subject_id = i.subject_id
  )
  AND p.gender = 'F'
  AND p.anchor_age BETWEEN 66 AND 76
),
sepsis_diagnosis AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%sepsis%'
),
sepsis_patients AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.stay_id,
    f.intime,
    f.gender,
    f.anchor_age,
    CASE WHEN s.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_sepsis
  FROM first_icu f
  LEFT JOIN sepsis_diagnosis s
    ON f.hadm_id = s.hadm_id
),
procedure_counts AS (
  SELECT 
    f.subject_id,
    COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM first_icu f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.stay_id = pe.stay_id
    AND pe.starttime >= f.intime
    AND pe.starttime <= f.intime + INTERVAL '48' HOUR
  GROUP BY f.subject_id
),
admissions_info AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
combined AS (
  SELECT 
    sp.has_sepsis,
    pc.num_procedures,
    ai.los_days,
    ai.hospital_expire_flag
  FROM sepsis_patients sp
  JOIN procedure_counts pc ON sp.subject_id = pc.subject_id
  JOIN admissions_info ai ON sp.hadm_id = ai.hadm_id
)
SELECT 
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY num_procedures) FILTER (WHERE has_sepsis = 1) AS percentile_90_procedures,
  AVG(los_days) FILTER (WHERE has_sepsis = 1) AS avg_los_sepsis,
  AVG(los_days) FILTER (WHERE has_sepsis = 0) AS avg_los_control,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) FILTER (WHERE has_sepsis = 1) AS mortality_sepsis,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) FILTER (WHERE has_sepsis = 0) AS mortality_control
FROM combined;