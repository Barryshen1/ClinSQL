WITH icu_stays AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id, 
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 48 AND 58
),
hr_data AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN icu_stays i 
    ON ce.stay_id = i.stay_id
  WHERE 
    ce.itemid = 220045  -- Heart Rate
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime < DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
  GROUP BY ce.stay_id
),
aki_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '584%') 
    OR (icd_version = 10 AND icd_code LIKE 'N17%')
),
combined_data AS (
  SELECT 
    i.stay_id,
    h.avg_hr,
    CASE 
      WHEN h.avg_hr < 60 THEN '<60'
      WHEN h.avg_hr BETWEEN 60 AND 99 THEN '60-99'
      WHEN h.avg_hr BETWEEN 100 AND 119 THEN '100-119'
      WHEN h.avg_hr >= 120 THEN '>=120'
      ELSE NULL 
    END AS hr_category,
    CASE WHEN a.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS aki_flag
  FROM icu_stays i
  INNER JOIN hr_data h 
    ON i.stay_id = h.stay_id
  LEFT JOIN aki_diagnoses a 
    ON i.hadm_id = a.hadm_id
)
SELECT 
  hr_category,
  COUNT(*) AS num_stays,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percent_distribution,
  AVG(aki_flag) * 100 AS aki_rate
FROM combined_data
GROUP BY hr_category
ORDER BY 
  CASE hr_category
    WHEN '<60' THEN 1
    WHEN '60-99' THEN 2
    WHEN '100-119' THEN 3
    WHEN '>=120' THEN 4
  END;