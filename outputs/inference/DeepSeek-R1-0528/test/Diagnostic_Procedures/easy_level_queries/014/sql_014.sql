WITH device_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE 
    LOWER(long_title) LIKE '%intra-aortic balloon%' OR
    LOWER(long_title) LIKE '%ventricular assist%' OR
    LOWER(long_title) LIKE '%extracorporeal membrane oxygenation%' OR
    LOWER(long_title) LIKE '%ecmo%' OR
    LOWER(long_title) LIKE '%heart-assist%' OR
    LOWER(long_title) LIKE '%counterpulsation%' OR
    LOWER(long_title) LIKE '%iabp%'
),
patient_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' AND 
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
),
device_procedures AS (
  SELECT proc.hadm_id, proc.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN device_codes dc
    ON proc.icd_code = dc.icd_code AND proc.icd_version = dc.icd_version
),
device_events AS (
  SELECT 
    pa.hadm_id,
    dp.icd_code
  FROM patient_admissions pa
  LEFT JOIN device_procedures dp
    ON pa.hadm_id = dp.hadm_id
),
counts AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT icd_code) AS device_count
  FROM device_events
  GROUP BY hadm_id
)
SELECT 
  APPROX_QUANTILES(device_count, 2)[SAFE_OFFSET(1)] AS median_device_count
FROM counts;