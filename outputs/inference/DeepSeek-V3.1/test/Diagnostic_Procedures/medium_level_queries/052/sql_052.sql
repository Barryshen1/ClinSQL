WITH ultrasound_procedures AS (
  SELECT 
    proc.hadm_id,
    COUNT(DISTINCT proc.seq_num) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dicd
    ON proc.icd_code = dicd.icd_code 
    AND proc.icd_version = dicd.icd_version
  WHERE LOWER(dicd.long_title) LIKE '%ultrasound%' 
    OR LOWER(dicd.long_title) LIKE '%echocardiogram%'
  GROUP BY proc.hadm_id
),
icu_stays_filtered AS (
  SELECT 
    icu.hadm_id,
    icu.los,
    adm.admission_type,
    CASE 
      WHEN adm.admission_type = 'ELECTIVE' THEN 'ELECTIVE'
      WHEN adm.admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED'
      ELSE 'OTHER' 
    END AS admission_category,
    CASE 
      WHEN icu.los BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN icu.los BETWEEN 3 AND 7 THEN '4-7 days'
      ELSE 'Other' 
    END AS stay_length_group
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 73 AND 83
    AND icu.los BETWEEN 1 AND 7
)
SELECT 
  admission_category,
  stay_length_group,
  COUNT(DISTINCT isf.hadm_id) AS num_admissions,
  AVG(COALESCE(up.ultrasound_count, 0)) AS mean_ultrasounds,
  MIN(COALESCE(up.ultrasound_count, 0)) AS min_ultrasounds,
  MAX(COALESCE(up.ultrasound_count, 0)) AS max_ultrasounds
FROM icu_stays_filtered isf
LEFT JOIN ultrasound_procedures up
  ON isf.hadm_id = up.hadm_id
WHERE stay_length_group IN ('1-3 days', '4-7 days')
  AND admission_category IN ('ED', 'ELECTIVE')
GROUP BY admission_category, stay_length_group
ORDER BY admission_category, stay_length_group;