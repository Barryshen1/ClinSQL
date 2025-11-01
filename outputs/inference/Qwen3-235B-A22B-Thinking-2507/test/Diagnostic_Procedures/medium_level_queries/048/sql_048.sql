WITH hf_diagnosis_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    LOWER(long_title) LIKE '%heart failure%' 
    OR LOWER(long_title) LIKE '%congestive heart failure%'
),
patients_90_100_m AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE 
    gender = 'M' 
    AND anchor_age BETWEEN 90 AND 100
),
admissions_with_hf AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    MAX(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) AS has_primary_hf
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patients_90_100_m p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN hf_diagnosis_codes hfc 
    ON d.icd_code = hfc.icd_code AND d.icd_version = hfc.icd_version
  GROUP BY a.hadm_id, a.subject_id, a.admittime, a.dischtime
),
imaging_procedures AS (
  SELECT 
    code AS hcpcs_cd
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE 
    LOWER(short_description) LIKE '%computed tomography%' 
    OR LOWER(short_description) LIKE '%ct scan%'
    OR LOWER(long_description) LIKE '%computed tomography%'
    OR LOWER(long_description) LIKE '%ct scan%'
    OR LOWER(short_description) LIKE '%magnetic resonance imaging%'
    OR LOWER(short_description) LIKE '%mri%'
    OR LOWER(long_description) LIKE '%magnetic resonance imaging%'
    OR LOWER(long_description) LIKE '%mri%'
),
mri_ct_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS mri_ct_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE hcpcs_cd IN (SELECT hcpcs_cd FROM imaging_procedures)
  GROUP BY hadm_id
)
SELECT
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
  END AS los_group,
  CASE 
    WHEN has_primary_hf = 1 THEN 'primary'
    ELSE 'secondary'
  END AS diagnosis_type,
  COUNT(*) AS admission_count,
  AVG(COALESCE(m.mri_ct_count, 0)) AS mean_mri_ct_per_admission
FROM admissions_with_hf a
LEFT JOIN mri_ct_counts m ON a.hadm_id = m.hadm_id
WHERE 
  los_days BETWEEN 1 AND 7
GROUP BY los_group, diagnosis_type
HAVING los_group IS NOT NULL
ORDER BY los_group, diagnosis_type;