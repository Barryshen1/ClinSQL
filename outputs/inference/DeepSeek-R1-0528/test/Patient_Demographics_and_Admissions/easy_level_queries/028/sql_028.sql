SELECT STDDEV(los) AS stddev_icu_los_days
FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON icu.subject_id = p.subject_id
WHERE 
  p.gender = 'M' 
  AND p.anchor_age BETWEEN 90 AND 100
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    WHERE 
      diag.hadm_id = icu.hadm_id
      AND (
        -- ICD-9 codes for sepsis
        (diag.icd_version = 9 AND (
          diag.icd_code LIKE '038%' OR 
          diag.icd_code IN ('785.52', '995.91', '995.92')
        )) 
        OR 
        -- ICD-10 codes for sepsis
        (diag.icd_version = 10 AND (
          diag.icd_code LIKE 'A40%' OR 
          diag.icd_code LIKE 'A41%' OR 
          diag.icd_code LIKE 'R65.2%'
        ))
      )
  );