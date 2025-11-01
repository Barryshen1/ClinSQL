WITH icu_patients AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
),
heart_rate AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS mean_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE itemid = 211
    AND valuenum IS NOT NULL
  GROUP BY stay_id
),
acute_mi AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN (icd_version = 9 AND icd_code LIKE '410%') 
        OR (icd_version = 10 AND icd_code LIKE 'I21%') 
      THEN 1 
      ELSE 0 
    END) AS has_acute_mi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
)
SELECT 
  CASE 
    WHEN hr.mean_hr < 60 THEN '<60'
    WHEN hr.mean_hr BETWEEN 60 AND 99 THEN '60-99'
    WHEN hr.mean_hr BETWEEN 100 AND 119 THEN '100-119'
    ELSE '≥120'
  END AS hr_category,
  COUNT(*) AS count,
  ROUND(AVG(acute_mi.has_acute_mi) * 100, 2) AS percent_with_acute_mi
FROM icu_patients ip
JOIN heart_rate hr ON ip.stay_id = hr.stay_id
LEFT JOIN acute_mi ON ip.hadm_id = acute_mi.hadm_id
GROUP BY hr_category
ORDER BY hr_category;