WITH admissions_data AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
imaging_counts AS (
  SELECT
    p.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d 
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ct%'
    OR LOWER(d.long_title) LIKE '%mri%'
    OR LOWER(d.long_title) LIKE '%x-ray%'
    OR LOWER(d.long_title) LIKE '%ultrasound%'
    OR LOWER(d.long_title) LIKE '%imaging%'
    OR LOWER(d.long_title) LIKE '%radiology%'
    OR LOWER(d.long_title) LIKE '%fluoroscopy%'
    OR LOWER(d.long_title) LIKE '%nuclear medicine%'
    OR LOWER(d.long_title) LIKE '%pet%'
    OR LOWER(d.long_title) LIKE '%mammography%'
    OR LOWER(d.long_title) LIKE '%bone density%'
    OR LOWER(d.long_title) LIKE '%dxa%'
    OR LOWER(d.long_title) LIKE '%sonography%'
    OR LOWER(d.long_title) LIKE '%diagnostic imaging%'
  GROUP BY p.hadm_id
)
SELECT
  ad.icu_use,
  CASE
    WHEN ad.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN ad.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  COUNT(*) AS admission_count,
  AVG(COALESCE(ic.imaging_count, 0)) AS mean_imaging_procedures
FROM admissions_data ad
LEFT JOIN imaging_counts ic ON ad.hadm_id = ic.hadm_id
GROUP BY icu_use, los_group
ORDER BY icu_use, los_group;