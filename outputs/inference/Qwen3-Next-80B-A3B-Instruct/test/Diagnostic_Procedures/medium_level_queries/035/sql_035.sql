WITH akimale AS (
  SELECT 
    a.hadm_id,
    p.anchor_age,
    p.gender,
    di.icd_code,
    di.icd_version,
    di.seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  WHERE p.anchor_age BETWEEN 43 AND 53
    AND p.gender = 'M'
    AND di.icd_version IN (9, 10)
    AND (
      (di.icd_version = 10 AND di.icd_code IN ('N17.0', 'N17.1', 'N17.2', 'N17.8', 'N17.9'))
      OR
      (di.icd_version = 9 AND di.icd_code IN ('584.9', '584.5', '584.6', '584.7', '584.8', '584.0', '584.1', '584.2', '584.3', '584.4'))
    )
),
aki_type AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN seq_num = 1 THEN 'Primary AKI'
      ELSE 'Secondary AKI'
    END AS aki_type
  FROM akimale
),
ct_mri_counts AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS num_ct_mri
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  WHERE p.icd_version = 9
    AND (
      p.icd_code LIKE '88.4%'  -- CT scans
      OR p.icd_code LIKE '88.5%'  -- MRI scans
    )
  GROUP BY p.hadm_id
),
los_groups AS (
  SELECT 
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE NULL 
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE dischtime IS NOT NULL
)
SELECT 
  lg.los_group,
  at.aki_type,
  COUNT(DISTINCT lg.hadm_id) AS patient_count,
  AVG(cm.num_ct_mri) AS mean_mri_ct_per_admission
FROM los_groups lg
INNER JOIN aki_type at ON lg.hadm_id = at.hadm_id
LEFT JOIN ct_mri_counts cm ON lg.hadm_id = cm.hadm_id
WHERE lg.los_group IS NOT NULL
GROUP BY lg.los_group, at.aki_type
ORDER BY lg.los_group, at.aki_type;