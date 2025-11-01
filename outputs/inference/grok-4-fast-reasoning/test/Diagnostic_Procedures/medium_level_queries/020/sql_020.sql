WITH imaging_procs AS (
  SELECT 
    pi.subject_id, 
    pi.hadm_id, 
    COUNT(*) AS num_imaging
  FROM 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code 
    AND pi.icd_version = dip.icd_version
  WHERE 
    LOWER(dip.long_title) LIKE '%ct%'
    OR LOWER(dip.long_title) LIKE '%mri%'
    OR LOWER(dip.long_title) LIKE '%magnetic resonance%'
    OR LOWER(dip.long_title) LIKE '%x-ray%'
    OR LOWER(dip.long_title) LIKE '%radiograph%'
    OR LOWER(dip.long_title) LIKE '%ultrasound%'
    OR LOWER(dip.long_title) LIKE '%echocardiography%'
    OR LOWER(dip.long_title) LIKE '%nuclear medicine%'
    OR LOWER(dip.long_title) LIKE '%tomography%'
    OR LOWER(dip.long_title) LIKE '%angiography%'
  GROUP BY 
    pi.subject_id, pi.hadm_id
),
cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    EXTRACT(DAY FROM (DATE(a.dischtime) - DATE(a.admittime))) AS los_days,
    CASE 
      WHEN EXTRACT(DAY FROM (DATE(a.dischtime) - DATE(a.admittime))) BETWEEN 1 AND 3 THEN '1-3'
      WHEN EXTRACT(DAY FROM (DATE(a.dischtime) - DATE(a.admittime))) BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND EXTRACT(DAY FROM (DATE(a.dischtime) - DATE(a.admittime))) BETWEEN 1 AND 7
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.subject_id = a.subject_id 
        AND di.hadm_id = a.hadm_id 
        AND di.icd_code IN ('4359', 'G459')
    )
)
SELECT 
  c.los_group,
  CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS icu_use,
  COUNT(DISTINCT c.hadm_id) AS admission_count,
  ROUND(AVG(COALESCE(ip.num_imaging, 0)), 2) AS mean_diagnostic_imaging_procs
FROM 
  cohort c
LEFT JOIN 
  `physionet-data.mimiciv_3_1_icu.icustays` i 
  ON c.hadm_id = i.hadm_id
LEFT JOIN 
  imaging_procs ip 
  ON c.hadm_id = ip.hadm_id 
  AND c.subject_id = ip.subject_id
GROUP BY 
  c.los_group, 
  CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END
ORDER BY 
  los_group, 
  CASE WHEN icu_use = 'Yes' THEN 1 ELSE 0 END;