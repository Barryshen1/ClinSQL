WITH patient_icu_stays AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.hadm_id,
    i.intime,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 48 AND 58
),
hr_data AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS avg_hr_48h
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN patient_icu_stays pis
    ON ce.stay_id = pis.stay_id
  WHERE di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= pis.intime
    AND ce.charttime <= DATETIME_ADD(pis.intime, INTERVAL 48 HOUR)
  GROUP BY ce.stay_id
),
aki_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'N17%'
    AND di.icd_version = 10
),
stay_summary AS (
  SELECT 
    pis.stay_id,
    hr.avg_hr_48h,
    CASE 
      WHEN hr.avg_hr_48h < 60 THEN '<60'
      WHEN hr.avg_hr_48h BETWEEN 60 AND 99 THEN '60-99'
      WHEN hr.avg_hr_48h BETWEEN 100 AND 119 THEN '100-119'
      WHEN hr.avg_hr_48h >= 120 THEN '>=120'
      ELSE NULL
    END AS hr_category,
    CASE WHEN aki.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki
  FROM patient_icu_stays pis
  LEFT JOIN hr_data hr ON pis.stay_id = hr.stay_id
  LEFT JOIN aki_diagnoses aki ON pis.hadm_id = aki.hadm_id
),
hr_distribution AS (
  SELECT
    hr_category,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS percent
  FROM stay_summary
  WHERE hr_category IS NOT NULL
  GROUP BY hr_category
),
aki_rate AS (
  SELECT
    AVG(CAST(has_aki AS FLOAT64)) * 100 AS aki_rate_percent
  FROM stay_summary
)
SELECT
  'HR Category' AS metric_type,
  hr_category AS category,
  ROUND(percent, 2) AS value
FROM hr_distribution
UNION ALL
SELECT
  'AKI Rate' AS metric_type,
  'Any AKI' AS category,
  ROUND(aki_rate_percent, 2) AS value
FROM aki_rate
ORDER BY metric_type DESC, category;