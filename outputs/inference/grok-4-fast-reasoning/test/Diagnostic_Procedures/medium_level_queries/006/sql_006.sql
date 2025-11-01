WITH eligible_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 4 THEN '1-4' 
      ELSE '5-8' 
    END AS los_bin,
    CASE 
      WHEN EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i WHERE i.hadm_id = a.hadm_id) 
      THEN 'ICU' 
      ELSE 'No ICU' 
    END AS icu_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id 
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND (di.icd_code LIKE 'A40.%' OR di.icd_code LIKE 'A41.%' OR di.icd_code = 'R65.20'))
          OR
          (di.icd_version = 9 AND (di.icd_code LIKE '038.%' OR di.icd_code = '995.91'))
        )
    )
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id 
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND di.icd_code = 'R65.21')
          OR
          (di.icd_version = 9 AND di.icd_code = '785.52')
        )
    )
),
ultrasound_counts AS (
  SELECT 
    pi.hadm_id, 
    COUNT(*) AS num_ultrasounds
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dp 
    ON pi.icd_code = dp.icd_code 
    AND pi.icd_version = dp.icd_version
  WHERE LOWER(dp.long_title) LIKE '%ultrasound%'
  GROUP BY pi.hadm_id
)
SELECT 
  ea.los_bin, 
  ea.icu_flag,
  COUNT(DISTINCT ea.subject_id) AS patient_counts,
  AVG(COALESCE(uc.num_ultrasounds, 0)) AS mean_ultrasounds_per_admission
FROM eligible_admissions ea
LEFT JOIN ultrasound_counts uc ON ea.hadm_id = uc.hadm_id
GROUP BY ea.los_bin, ea.icu_flag
ORDER BY los_bin, icu_flag;