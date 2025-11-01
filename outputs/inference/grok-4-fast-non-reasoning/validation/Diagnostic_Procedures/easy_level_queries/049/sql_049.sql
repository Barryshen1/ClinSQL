WITH patient_procedures AS (
  SELECT 
    p.subject_id,
    COUNT(DISTINCT proc.icd_code) AS distinct_ecg_codes
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON p.subject_id = proc.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON proc.hadm_id = adm.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND adm.hospital_expire_flag = 0
    AND proc.icd_code LIKE '4A%'  -- ICD-10-PCS codes for cardiac monitoring/telemetry/ECG
  GROUP BY 
    p.subject_id
)
SELECT 
  STDDEV(distinct_ecg_codes) AS sd_distinct_ecg_telemetry_codes
FROM 
  patient_procedures;