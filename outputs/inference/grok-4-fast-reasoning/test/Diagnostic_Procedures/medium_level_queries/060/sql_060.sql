WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los,
    (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id) > 0 AS has_icu
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id AND diag.seq_num = 1
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      (diag.icd_version = 'ICD-9' AND diag.icd_code LIKE '428%') 
      OR 
      (diag.icd_version = 'ICD-10' AND diag.icd_code LIKE 'I50%')
    )
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
ctmri_counts AS (
  SELECT 
    c.hadm_id,
    COUNT(p.icd_code) AS num_ctmri
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON c.hadm_id = p.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip ON p.icd_code = dip.icd_code 
    AND p.icd_version = dip.icd_version
  WHERE 
    (dip.long_title LIKE '%CT%' OR dip.long_title LIKE '%MRI%')
  GROUP BY 
    c.hadm_id
)
SELECT 
  CASE 
    WHEN c.los <= 4 THEN '1-4 days'
    ELSE '5-7 days'
  END AS los_group,
  CASE 
    WHEN c.has_icu THEN 'ICU: Yes'
    ELSE 'ICU: No'
  END AS icu_group,
  COUNT(*) AS admission_count,
  AVG(COALESCE(cc.num_ctmri, 0)) AS mean_ctmri_per_admission
FROM 
  cohort c
LEFT JOIN 
  ctmri_counts cc ON c.hadm_id = cc.hadm_id
GROUP BY 
  los_group, icu_group
ORDER BY 
  los_group, icu_group;