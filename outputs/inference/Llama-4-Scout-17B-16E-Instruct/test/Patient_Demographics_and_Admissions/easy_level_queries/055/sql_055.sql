WITH patient_data AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
),
pneumonia_patients AS (
  SELECT 
    pd.hadm_id
  FROM 
    patient_data pd
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON 
    pd.hadm_id = di.hadm_id
  WHERE 
    di.icd_code LIKE '481%'  -- ICD-9 code for pneumonia
    OR di.icd_code LIKE 'J18%'  -- ICD-10 code for pneumonia
)
SELECT 
  APPROX_QUANTILES(TIMESTAMP_DIFF(pa.dischtime, pa.admittime, DAY), 100)[25] AS percentile_25_los
FROM 
  patient_data pa
JOIN 
  pneumonia_patients pp
ON 
  pa.hadm_id = pp.hadm_id
WHERE 
  pa.dischtime IS NOT NULL;