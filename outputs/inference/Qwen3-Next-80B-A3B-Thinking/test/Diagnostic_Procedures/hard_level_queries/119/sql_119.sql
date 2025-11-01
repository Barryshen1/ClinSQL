WITH icu_patients AS (
  SELECT
    a.hadm_id,
    i.stay_id,
    i.intime,
    p.gender,
    (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) AS admission_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age)) BETWEEN 42 AND 52
),
ami_status AS (
  SELECT
    a.hadm_id,
    MAX(CASE WHEN d.long_title LIKE '%myocardial infarction%' THEN 1 ELSE 0 END) AS has_ami
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_icd ON a.hadm_id = d_icd.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON d_icd.icd_code = d.icd_code AND d_icd.icd_version = d.icd_version
  GROUP BY a.hadm_id
),
procedure_counts AS (
  SELECT
    i.stay_id,
    COUNT(DISTINCT pe.itemid) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
    ON i.stay_id = pe.stay_id
  WHERE pe.starttime BETWEEN i.intime AND i.intime + INTERVAL 72 HOUR
  GROUP BY i.stay_id
),
admissions_data AS (
  SELECT
    a.hadm_id,
    a.dischtime - a.admittime AS los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
)
SELECT
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY CASE WHEN as_.has_ami = 1 THEN pc.num_procedures END) AS percentile_90_procedures,
  AVG(CASE WHEN as_.has_ami = 1 THEN ad.los END) AS mean_los_ami,
  AVG(CASE WHEN as_.has_ami = 0 THEN ad.los END) AS mean_los_non_ami,
  AVG(CASE WHEN as_.has_ami = 1 THEN ad.hospital_expire_flag END) AS mortality_ami,
  AVG(CASE WHEN as_.has_ami = 0 THEN ad.hospital_expire_flag END) AS mortality_non_ami
FROM icu_patients ip
JOIN ami_status as_ ON ip.hadm_id = as_.hadm_id
JOIN admissions_data ad ON ip.hadm_id = ad.hadm_id
LEFT JOIN procedure_counts pc ON ip.stay_id = pc.stay_id
WHERE as_.has_ami IS NOT NULL;