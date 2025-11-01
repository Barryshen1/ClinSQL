WITH eligible_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) BETWEEN 1 AND 7
),
procedure_counts AS (
  SELECT 
    ea.*,
    COUNT(DISTINCT pi.icd_code) AS procedure_count  -- Distinct to avoid duplicate codes per admission
  FROM 
    eligible_admissions ea
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  ON 
    ea.subject_id = pi.subject_id 
    AND ea.hadm_id = pi.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
  ON 
    pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE 
    (LOWER(dip.long_title) LIKE '%ct%' 
     OR LOWER(dip.long_title) LIKE '%tomography%' 
     OR LOWER(dip.long_title) LIKE '%x-ray%' 
     OR LOWER(dip.long_title) LIKE '%radiography%' 
     OR LOWER(dip.long_title) LIKE '%mri%')
  GROUP BY 
    ea.subject_id, ea.hadm_id, ea.admittime, ea.dischtime, ea.los_days, ea.los_group
)
SELECT 
  los_group,
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  ROUND(AVG(procedure_count), 2) AS mean_radiography_ct_procedures_per_admission
FROM 
  procedure_counts
GROUP BY 
  los_group
ORDER BY 
  los_group;