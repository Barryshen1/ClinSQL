WITH pancreatitis_dx AS (
  SELECT DISTINCT di.subject_id, di.hadm_id, di.seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON di.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND (
      (di.icd_version = 9 AND di.icd_code = '5770') OR
      (di.icd_version = 10 AND di.icd_code LIKE 'K85%')
    )
),
admissions_with_pan AS (
  SELECT 
    awp.subject_id, 
    awp.hadm_id, 
    awp.dx_type, 
    a.admittime, 
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM (
    SELECT 
      subject_id, 
      hadm_id,
      CASE WHEN MIN(seq_num) = 1 THEN 'primary' ELSE 'secondary' END AS dx_type
    FROM pancreatitis_dx
    GROUP BY subject_id, hadm_id
  ) awp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON awp.hadm_id = a.hadm_id
  WHERE TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
imaging_procs AS (
  SELECT 
    pi.hadm_id, 
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%ct%' 
     OR LOWER(dip.long_title) LIKE '%computed tomography%' 
     OR LOWER(dip.long_title) LIKE '%x-ray%' 
     OR LOWER(dip.long_title) LIKE '%radiography%' 
     OR LOWER(dip.long_title) LIKE '%radiologic%'
  GROUP BY pi.hadm_id
)
SELECT 
  awp.dx_type,
  CASE WHEN awp.los_days <= 3 THEN '1-3' ELSE '4-7' END AS los_group,
  COUNT(DISTINCT awp.subject_id) AS patient_count,
  AVG(COALESCE(ip.imaging_count, 0)) AS mean_imaging_per_admission
FROM admissions_with_pan awp
LEFT JOIN imaging_procs ip ON awp.hadm_id = ip.hadm_id
GROUP BY awp.dx_type, los_group
ORDER BY dx_type, los_group;