WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 90 AND 100
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
imaging_procedures AS (
  SELECT DISTINCT
    pi.hadm_id,
    pi.icd_code,
    pi.icd_version
  FROM 
    physionet-data.mimiciv_3_1_hosp.procedures_icd pi
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE 
    LOWER(dip.long_title) LIKE '%ct%' 
    OR LOWER(dip.long_title) LIKE '%mri%' 
    OR LOWER(dip.long_title) LIKE '%x-ray%' 
    OR LOWER(dip.long_title) LIKE '%ultrasound%' 
    OR LOWER(dip.long_title) LIKE '%us%' 
    OR LOWER(dip.long_title) LIKE '%imaging%' 
    OR LOWER(dip.long_title) LIKE '%scan%' 
    OR LOWER(dip.long_title) LIKE '%radiograph%' 
    OR LOWER(dip.long_title) LIKE '%fluoroscopy%' 
    OR LOWER(dip.long_title) LIKE '%angiography%' 
    OR LOWER(dip.long_title) LIKE '%nuclear%'
),
admission_imaging_counts AS (
  SELECT 
    pa.hadm_id,
    pa.los_days,
    COUNT(ip.icd_code) AS imaging_procedure_count
  FROM 
    patient_admissions pa
  LEFT JOIN 
    imaging_procedures ip
    ON pa.hadm_id = ip.hadm_id
  GROUP BY 
    pa.hadm_id, pa.los_days
),
los_groups AS (
  SELECT 
    imaging_procedure_count,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group
  FROM 
    admission_imaging_counts
  WHERE 
    los_days BETWEEN 1 AND 7  -- Only consider 1-7 day stays as per question
)
SELECT 
  los_group,
  AVG(imaging_procedure_count) AS mean_imaging_procedures,
  MIN(imaging_procedure_count) AS min_imaging_procedures,
  MAX(imaging_procedure_count) AS max_imaging_procedures
FROM 
  los_groups
WHERE 
  los_group IS NOT NULL
GROUP BY 
  los_group
ORDER BY 
  los_group;