WITH icu_patients AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    p.anchor_age,
    p.gender
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 62 AND 72
    AND p.gender = 'M'
),
heart_rate_means AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS mean_heart_rate
  FROM 
    physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300  -- reasonable physiological range
  GROUP BY 
    ce.stay_id
),
mi_diagnoses AS (
  SELECT DISTINCT
    i.stay_id
  FROM 
    physionet-data.mimiciv_3_1_icu.icustays i
  JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON i.hadm_id = di.hadm_id
  WHERE 
    (di.icd_code LIKE '410%' AND di.icd_version = 9)
    OR (di.icd_code LIKE 'I21%' AND di.icd_version = 10)
    OR (di.icd_code LIKE 'I22%' AND di.icd_version = 10)
),
combined AS (
  SELECT 
    ip.stay_id,
    hr.mean_heart_rate,
    CASE 
      WHEN hr.mean_heart_rate < 60 THEN '<60'
      WHEN hr.mean_heart_rate BETWEEN 60 AND 99 THEN '60-99'
      WHEN hr.mean_heart_rate BETWEEN 100 AND 119 THEN '100-119'
      WHEN hr.mean_heart_rate >= 120 THEN '≥120'
    END AS hr_category,
    CASE WHEN mi.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_mi
  FROM 
    icu_patients ip
  JOIN 
    heart_rate_means hr ON ip.stay_id = hr.stay_id
  LEFT JOIN 
    mi_diagnoses mi ON ip.stay_id = mi.stay_id
)
SELECT 
  hr_category,
  COUNT(*) AS count_per_icu_stay,
  ROUND(100.0 * SUM(has_mi) / COUNT(*), 2) AS percent_with_acute_mi
FROM 
  combined
GROUP BY 
  hr_category
ORDER BY 
  hr_category;