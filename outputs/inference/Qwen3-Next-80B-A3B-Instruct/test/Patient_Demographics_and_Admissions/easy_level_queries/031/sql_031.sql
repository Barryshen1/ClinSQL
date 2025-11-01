WITH first_hf_admission AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_icd ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND (
      d.icd_code LIKE '428.%'  -- ICD-9 heart failure codes
      OR d.icd_code LIKE 'I50%' -- ICD-10 heart failure codes
    )
    AND a.hospital_expire_flag = 0  -- exclude those who died in admission
),

ranked_hf AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM first_hf_admission
),

first_hf_only AS (
  SELECT *
  FROM ranked_hf
  WHERE rn = 1
),

readmissions AS (
  SELECT 
    f.subject_id,
    f.hadm_id AS first_hadm_id,
    f.admittime AS first_admittime,
    a.hadm_id AS readmit_hadm_id,
    a.admittime AS readmit_admittime
  FROM first_hf_only f
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a ON f.subject_id = a.subject_id
  WHERE a.admittime > f.admittime
    AND a.admittime <= DATE_ADD(f.admittime, INTERVAL 30 DAY)
)

SELECT 
  AVG(CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1.0 ELSE 0.0 END) AS avg_30day_readmission_rate
FROM first_hf_only f
LEFT JOIN readmissions r ON f.subject_id = r.subject_id;