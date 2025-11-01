WITH 
-- Filter admissions based on age, gender, and LOS
admissions_filtered AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         p.subject_id, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age BETWEEN 45 AND 55
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Identify HF admissions and primary/secondary diagnosis
hf_admissions AS (
  SELECT af.hadm_id, af.los,
         CASE 
           WHEN di.icd_code IS NOT NULL AND d.diag_seq_num = 1 THEN 'Primary'
           WHEN di.icd_code IS NOT NULL THEN 'Secondary'
           ELSE 'Non-HF'
         END AS hf_diagnosis_type
  FROM admissions_filtered af
  LEFT JOIN (
    SELECT hadm_id, MIN(seq_num) AS diag_seq_num
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE 'I50%'  -- Simplified HF diagnosis code
    GROUP BY hadm_id
  ) d ON af.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON af.hadm_id = di.hadm_id AND d.diag_seq_num = di.seq_num
),

-- Count CT/MRI for each admission (this part is simplified and might need adjustment based on actual data)
imaging_counts AS (
  SELECT h.hadm_id, 
         SUM(CASE WHEN h.hcpcs_cd LIKE '70450%' OR h.hcpcs_cd LIKE '72125%' THEN 1 ELSE 0 END) AS ct_mri_count  -- Example codes for CT/MRI
  FROM hf_admissions ha
  JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h ON ha.hadm_id = h.hadm_id
  GROUP BY h.hadm_id
)

-- Final aggregation
SELECT 
  hf_diagnosis_type,
  CASE WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
       WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_category,
  COUNT(*) AS num_admissions,
  AVG(ct_mri_count) AS mean_ct_mri,
  MIN(ct_mri_count) AS min_ct_mri,
  MAX(ct_mri_count) AS max_ct_mri
FROM hf_admissions ha
JOIN imaging_counts ic ON ha.hadm_id = ic.hadm_id
WHERE hf_diagnosis_type != 'Non-HF'
GROUP BY hf_diagnosis_type, los_category
ORDER BY hf_diagnosis_type, los_category;