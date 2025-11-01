SELECT 
  MAX(los) AS max_icu_los_days
FROM 
  `physionet-data.mimiciv_3_1_icu.icustays` i
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p
ON 
  i.subject_id = p.subject_id
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND i.hadm_id IN (
    SELECT 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE 
      icd_version = 9
      AND icd_code = '00.66'
  );