WITH icu_stays AS (
  SELECT 
    ic.stay_id,
    ic.hadm_id,
    ic.subject_id,
    ic.intime,
    a.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    ic.hadm_id = a.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
    AND ic.first_careunit IS NOT NULL
    AND ic.stay_id = (SELECT MIN(stay_id) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE hadm_id = ic.hadm_id)
),
sepsis_patients AS (
  SELECT 
    DISTINCT ip.hadm_id
  FROM 
    icu_stays ip
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON 
    ip.hadm_id = di.hadm_id
  WHERE 
    di.icd_code IN ('99591', '99592', '99593', '99594', '99890')
),
procedures_48hrs AS (
  SELECT 
    ips.hadm_id,
    COUNT(DISTINCT pe.itemid) AS procedures_count
  FROM 
    icu_stays ips
  JOIN 
    sepsis_patients sp ON ips.hadm_id = sp.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  ON 
    ips.hadm_id = pe.hadm_id
  WHERE 
    pe.starttime BETWEEN ips.intime AND TIMESTAMP_ADD(ips.intime, INTERVAL 48 HOUR)
  GROUP BY 
    ips.hadm_id
),
controls AS (
  SELECT 
    ic.hadm_id,
    ic.anchor_age,
    p.gender,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    ic.hadm_id = a.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    ic.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 66 AND 76
    AND ic.first_careunit IS NOT NULL
    AND ic.stay_id = (SELECT MIN(stay_id) FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE hadm_id = ic.hadm_id)
    AND a.hadm_id NOT IN (SELECT hadm_id FROM sepsis_patients)
)
SELECT 
  APPROX_QUANTILES(procedures_count, 0.9) AS percentile_90_procedures,
  AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS sepsis_mortality_rate,
  AVG(CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS control_mortality_rate,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS sepsis_hospital_LOS,
  AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY)) AS control_hospital_LOS
FROM 
  procedures_48hrs
  JOIN icu_stays ON procedures_48hrs.hadm_id = icu_stays.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON icu_stays.hadm_id = a.hadm_id
  CROSS JOIN 
  (SELECT 
     hadm_id,
     hospital_expire_flag,
     dischtime,
     admittime 
   FROM 
     controls
  ) AS c;