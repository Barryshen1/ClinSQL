WITH
-- Identify male patients aged 90-100 with heart failure
hf_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I50.%') OR
      (d.icd_version = 9 AND d.icd_code LIKE '428.%')
    )
),

-- Get admissions with LOS and primary/secondary HF diagnosis
admissions_with_los AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE WHEN d.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS hf_diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN hf_patients hf ON a.subject_id = hf.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE (
    (d.icd_version = 10 AND d.icd_code LIKE 'I50.%') OR
    (d.icd_version = 9 AND d.icd_code LIKE '428.%')
  )
),

-- Count MRI/CT procedures per admission
mri_ct_counts AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS mri_ct_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh ON h.hcpcs_cd = dh.code
  WHERE (
    h.hcpcs_cd LIKE '7055%' OR  -- MRI codes
    h.hcpcs_cd LIKE '7045%' OR  -- CT codes
    h.hcpcs_cd LIKE '7046%' OR
    h.hcpcs_cd LIKE '7047%' OR
    h.hcpcs_cd LIKE '7048%' OR
    h.hcpcs_cd LIKE '7049%'
  )
  GROUP BY h.subject_id, h.hadm_id
)

-- Final aggregation
SELECT
  CASE
    WHEN a.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN a.los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Other'
  END AS los_group,
  a.hf_diagnosis_type,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(COALESCE(m.mri_ct_count, 0)) AS avg_mri_ct_per_admission
FROM admissions_with_los a
LEFT JOIN mri_ct_counts m ON a.subject_id = m.subject_id AND a.hadm_id = m.hadm_id
WHERE a.los BETWEEN 1 AND 7
GROUP BY los_group, hf_diagnosis_type
ORDER BY los_group, hf_diagnosis_type;