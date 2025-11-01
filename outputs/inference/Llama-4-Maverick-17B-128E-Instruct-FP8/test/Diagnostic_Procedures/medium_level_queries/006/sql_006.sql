WITH 
sepsis_patients AS (
  SELECT DISTINCT h.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd h
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON h.icd_code = d.icd_code AND h.icd_version = d.icd_version
  WHERE d.long_title LIKE '%Sepsis%' AND h.icd_version = 10
),
filtered_patients AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 48 AND 58
  AND a.hadm_id IN (SELECT hadm_id FROM sepsis_patients)
),
icu_status AS (
  SELECT fp.hadm_id, 
         DATE_DIFF(fp.dischtime, fp.admittime, DAY) AS los,
         CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_status
  FROM filtered_patients fp
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON fp.hadm_id = i.hadm_id
),
ultrasound_counts AS (
  SELECT c.hadm_id, COUNT(*) AS num_ultrasounds
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents c
  JOIN `physionet-data.mimiciv_3_1_icu`.d_items d ON c.itemid = d.itemid
  WHERE d.label LIKE '%Ultrasound%'  
  GROUP BY c.hadm_id
)
SELECT 
  icu_status,
  CASE 
    WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los BETWEEN 5 AND 8 THEN '5-8 days'
    ELSE 'Other'
  END AS los_group,
  COUNT(DISTINCT hadm_id) AS patient_count,
  AVG(COALESCE(uc.num_ultrasounds, 0)) AS mean_ultrasounds_per_admission
FROM icu_status
LEFT JOIN ultrasound_counts uc ON icu_status.hadm_id = uc.hadm_id
WHERE los BETWEEN 1 AND 8
GROUP BY icu_status, 
         CASE 
           WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
           WHEN los BETWEEN 5 AND 8 THEN '5-8 days'
           ELSE 'Other'
         END
ORDER BY icu_status, 
         CASE 
           WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
           WHEN los BETWEEN 5 AND 8 THEN '5-8 days'
           ELSE 'Other'
         END;