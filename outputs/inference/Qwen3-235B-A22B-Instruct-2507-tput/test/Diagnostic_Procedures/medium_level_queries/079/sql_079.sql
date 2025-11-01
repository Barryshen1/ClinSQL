WITH lgib_admissions AS (
  SELECT 
    a.hadm_id,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    -- Determine if LGIB is primary diagnosis (seq_num = 1)
    CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS lgib_diagnosis_type,
    -- Length of stay in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'F'
    AND di.icd_version = 10
    AND d.icd_code IN ('K5700', 'K5710', 'K5720', 'K5730', 'K5780', 'K5790', 'K5701', 'K5711', 'K5721', 'K5731', 'K5781', 'K5791', 'K625', 'K558', 'K559')
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 71 AND 81
),
imaging_procedures AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp`.hcpcsevents h
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_hcpcs d ON h.hcpcs_cd = d.code
  WHERE h.hcpcs_cd IN ('74200', '74201', '74202', '74150', '74170', '74175', '74176', '74177', '74178') -- Common CT abdomen/pelvis codes
  GROUP BY h.hadm_id
),
admissions_with_imaging AS (
  SELECT 
    l.hadm_id,
    l.lgib_diagnosis_type,
    l.los_days,
    COALESCE(i.imaging_count, 0) AS imaging_count
  FROM lgib_admissions l
  LEFT JOIN imaging_procedures i ON l.hadm_id = i.hadm_id
),
los_groups AS (
  SELECT 
    hadm_id,
    lgib_diagnosis_type,
    imaging_count,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL 
    END AS los_group
  FROM admissions_with_imaging
  WHERE los_days IS NOT NULL
)
SELECT 
  los_group,
  lgib_diagnosis_type,
  AVG(imaging_count) AS mean_imaging_per_admission,
  COUNT(*) AS admission_count
FROM los_groups
WHERE los_group IS NOT NULL
GROUP BY los_group, lgib_diagnosis_type
ORDER BY los_group, lgib_diagnosis_type;