WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 71 AND 81
),
admissions_filtered AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p
    ON a.subject_id = p.subject_id
  WHERE a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
lgib_diagnoses AS (
  SELECT 
    d.hadm_id,
    d.seq_num,
    CASE WHEN d.icd_code IN (
      'K625', 'K570', 'K571', 'K572', 'K573', 'K574', 
      'K575', 'K578', 'K579', 'K5521', 'K5522', 'K635'
    ) THEN 1 ELSE 0 END AS is_lgib
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd d
  WHERE d.icd_version = 10
),
admission_lgib_status AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN seq_num = 1 AND is_lgib = 1 THEN 1 ELSE 0 END) AS is_primary,
    MAX(CASE WHEN is_lgib = 1 THEN 1 ELSE 0 END) AS has_lgib
  FROM lgib_diagnoses
  GROUP BY hadm_id
),
imaging_procedures AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS num_imaging
  FROM `physionet-data.mimiciv_3_1_hosp`.procedures_icd p
  WHERE p.icd_version = 10
    AND SUBSTR(p.icd_code, 3, 1) IN ('0', '3')
  GROUP BY p.hadm_id
),
base AS (
  SELECT 
    a.hadm_id,
    a.los_days,
    l.is_primary,
    COALESCE(i.num_imaging, 0) AS num_imaging
  FROM admissions_filtered a
  INNER JOIN admission_lgib_status l
    ON a.hadm_id = l.hadm_id
  LEFT JOIN imaging_procedures i
    ON a.hadm_id = i.hadm_id
  WHERE l.has_lgib = 1
    AND a.los_days >= 1
    AND a.los_days < 8
)
SELECT
  CASE 
    WHEN los_days >= 1 AND los_days < 4 THEN '1-3 days'
    WHEN los_days >= 4 AND los_days < 8 THEN '4-7 days'
  END AS stay_group,
  CASE 
    WHEN is_primary = 1 THEN 'primary'
    ELSE 'secondary'
  END AS diagnosis_group,
  AVG(num_imaging) AS mean_imaging_per_admission,
  COUNT(*) AS num_admissions
FROM base
GROUP BY stay_group, diagnosis_group
ORDER BY stay_group, diagnosis_group;