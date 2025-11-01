WITH patients_80_90 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 80 AND 90
),
hemorrhagic_stroke_admissions AS (
  SELECT a.hadm_id, a.dischtime - a.admittime AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE a.subject_id IN (SELECT subject_id FROM patients_80_90)
  AND dicd.long_title LIKE '%Hemorrhagic stroke%' AND a.dischtime IS NOT NULL AND a.admittime IS NOT NULL
),
ultrasound_counts AS (
  SELECT hadm_id, COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON c.itemid = di.itemid
  WHERE di.label LIKE '%Ultrasound%' OR di.label LIKE '%Echo%'
  GROUP BY hadm_id
)
SELECT 
  CASE 
    WHEN hsa.los BETWEEN INTERVAL 1 DAY AND INTERVAL 4 DAY THEN '1-4 days'
    WHEN hsa.los BETWEEN INTERVAL 5 DAY AND INTERVAL 7 DAY THEN '5-7 days'
  END AS los_category,
  COUNT(*) AS num_admissions,
  AVG(uc.ultrasound_count) AS mean_ultrasounds,
  MIN(uc.ultrasound_count) AS min_ultrasounds,
  MAX(uc.ultrasound_count) AS max_ultrasounds
FROM hemorrhagic_stroke_admissions hsa
LEFT JOIN ultrasound_counts uc ON hsa.hadm_id = uc.hadm_id
WHERE hsa.los BETWEEN INTERVAL 1 DAY AND INTERVAL 7 DAY
GROUP BY los_category
ORDER BY los_category;