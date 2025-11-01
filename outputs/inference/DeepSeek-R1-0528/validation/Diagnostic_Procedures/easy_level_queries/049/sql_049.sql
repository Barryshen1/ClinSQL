WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id 
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id 
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 81 AND 91
),
ecg_procedures AS (
  SELECT 
    c.subject_id, 
    proc.icd_code
  FROM 
    cohort c 
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc 
      ON c.subject_id = proc.subject_id 
      AND c.hadm_id = proc.hadm_id 
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
      ON proc.icd_code = d.icd_code 
      AND proc.icd_version = d.icd_version 
      AND REGEXP_CONTAINS(
        LOWER(d.long_title), 
        r'ecg|ekg|electrocardiogram|telemetry|cardiac monitoring|holter|event monitor|loop recorder'
      )
),
per_patient_counts AS (
  SELECT 
    subject_id, 
    COUNT(DISTINCT icd_code) AS num_distinct_ecg_codes
  FROM 
    ecg_procedures 
  GROUP BY 
    subject_id
)
SELECT 
  STDDEV_POP(num_distinct_ecg_codes) AS sd_distinct_ecg_codes
FROM 
  per_patient_counts;