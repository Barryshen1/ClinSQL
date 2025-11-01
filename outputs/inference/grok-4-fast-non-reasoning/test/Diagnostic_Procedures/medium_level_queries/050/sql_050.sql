WITH patient_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND a.hospital_expire_flag = 0
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
),
imaging_counts AS (
  SELECT 
    pa.hadm_id,
    COUNT(pi.icd_code) AS imaging_count,
    CASE 
      WHEN pa.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      ELSE '4-7 days'
    END AS los_category
  FROM 
    patient_admissions pa
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  ON pa.hadm_id = pi.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
  ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE 
    LOWER(dip.long_title) LIKE '%ct%' 
    OR LOWER(dip.long_title) LIKE '%mri%' 
    OR LOWER(dip.long_title) LIKE '%ultrasound%' 
    OR LOWER(dip.long_title) LIKE '%x-ray%' 
    OR LOWER(dip.long_title) LIKE '%angiography%' 
    OR LOWER(dip.long_title) LIKE '%tomography%'
  GROUP BY 
    pa.hadm_id, los_category
)
SELECT 
  los_category,
  COUNT(hadm_id) AS num_admissions,
  ROUND(AVG(imaging_count), 2) AS mean_imaging,
  MIN(imaging_count) AS min_imaging,
  MAX(imaging_count) AS max_imaging
FROM 
  imaging_counts
GROUP BY 
  los_category
ORDER BY 
  los_category;