WITH 
-- Patient and admission information
patient_info AS (
  SELECT 
    a.hadm_id,
    a.admission_type,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age = 74
    AND p.gender = 'F'
    AND a.admission_type IN ('Elective', 'ED/Urgent')
),

-- Heart failure diagnosis
heart_failure AS (
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code LIKE '428%'
),

-- Non-invasive diagnostics
diagnostics AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN di.long_title LIKE '%X-ray%' OR di.long_title LIKE '%CT%' OR di.long_title LIKE '%MRI%' THEN 'Imaging'
      WHEN di.long_title LIKE '%ECG%' OR di.long_title LIKE '%EEG%' OR di.long_title LIKE '%PFT%' THEN 'ECG/EEG/PFT'
      ELSE NULL
    END AS diagnostic_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` di 
      ON pi.icd_code = di.icd_code AND pi.icd_version = di.icd_version
  WHERE 
    di.long_title IS NOT NULL
),

-- Stay duration
stay_duration AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS stay_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
)

-- Combine information
SELECT 
  CASE 
    WHEN sd.stay_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN sd.stay_days BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'Other'
  END AS stay_category,
  pi.admission_type,
  COUNT(DISTINCT d.diagnostic_type) / COUNT(DISTINCT pi.hadm_id) AS mean_diagnostics_per_admission
FROM 
  patient_info pi
JOIN 
  heart_failure hf 
    ON pi.hadm_id = hf.hadm_id
JOIN 
  diagnostics d 
    ON pi.hadm_id = d.hadm_id
JOIN 
  stay_duration sd 
    ON pi.hadm_id = sd.hadm_id
GROUP BY 
  stay_category,
  pi.admission_type
ORDER BY 
  stay_category,
  pi.admission_type;