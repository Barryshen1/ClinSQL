WITH heart_failure_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age = 74
    AND d.icd_code LIKE 'I50.%'  -- Heart failure ICD-10 codes
),

diagnostic_procedures AS (
  SELECT
    h.hadm_id,
    h.hcpcs_cd,
    d.long_description,
    a.admission_type,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON h.hadm_id = a.hadm_id
  JOIN heart_failure_patients hf ON h.hadm_id = hf.hadm_id
  WHERE d.long_description LIKE '%X-RAY%'
     OR d.long_description LIKE '%MRI%'
     OR d.long_description LIKE '%CT%'
     OR d.long_description LIKE '%ULTRASOUND%'
     OR d.long_description LIKE '%ELECTROCARDIOGRAM%'
     OR d.long_description LIKE '%ELECTROENCEPHALOGRAM%'
     OR d.long_description LIKE '%PULMONARY FUNCTION TEST%'
),

admission_strata AS (
  SELECT
    hadm_id,
    admission_type,
    CASE
      WHEN length_of_stay BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN length_of_stay BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL
    END AS stay_duration
  FROM diagnostic_procedures
  WHERE length_of_stay BETWEEN 1 AND 7
)

SELECT
  admission_type,
  stay_duration,
  COUNT(DISTINCT hadm_id) AS num_admissions,
  AVG(procedure_count) AS mean_procedures_per_admission
FROM (
  SELECT
    a.hadm_id,
    a.admission_type,
    a.stay_duration,
    COUNT(DISTINCT d.hcpcs_cd) AS procedure_count
  FROM admission_strata a
  JOIN diagnostic_procedures d ON a.hadm_id = d.hadm_id
  GROUP BY a.hadm_id, a.admission_type, a.stay_duration
)
GROUP BY admission_type, stay_duration
ORDER BY admission_type, stay_duration;