WITH cohort AS (
  SELECT 
    ie.subject_id, 
    ie.hadm_id, 
    ie.stay_id, 
    ie.intime, 
    ie.outtime,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
),

temp_48h AS (
  SELECT 
    c.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 223761  -- Temperature Celsius
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime <= DATETIME_ADD(c.intime, INTERVAL 48 HOUR)
  GROUP BY c.stay_id
),

temp_categorized AS (
  SELECT 
    t.stay_id,
    t.avg_temp,
    CASE 
      WHEN t.avg_temp < 36.0 THEN '<36.0'
      WHEN t.avg_temp BETWEEN 36.0 AND 37.9 THEN '36.0-37.9'
      WHEN t.avg_temp >= 38.0 THEN '>=38.0'
    END AS temp_category
  FROM temp_48h t
),

mi_diagnosis AS (
  SELECT 
    c.stay_id,
    MAX(
      CASE 
        WHEN di.icd_code LIKE '410%' AND di.icd_version = 9 THEN 1
        WHEN di.icd_code LIKE 'I21%' AND di.icd_version = 10 THEN 1
        WHEN di.icd_code LIKE 'I22%' AND di.icd_version = 10 THEN 1
        ELSE 0 
      END
    ) AS mi_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.hadm_id = di.hadm_id
  GROUP BY c.stay_id
)

SELECT 
  tc.temp_category,
  COUNT(*) AS num_stays,
  AVG(tc.avg_temp) AS mean_avg_temp,
  APPROX_QUANTILES(tc.avg_temp, 100)[OFFSET(50)] AS median_avg_temp,
  APPROX_QUANTILES(tc.avg_temp, 100)[OFFSET(25)] AS q1_avg_temp,
  APPROX_QUANTILES(tc.avg_temp, 100)[OFFSET(75)] AS q3_avg_temp,
  SUM(mi.mi_flag) AS mi_count,
  AVG(mi.mi_flag) AS mi_rate
FROM temp_categorized tc
INNER JOIN mi_diagnosis mi
  ON tc.stay_id = mi.stay_id
GROUP BY tc.temp_category
ORDER BY 
  CASE 
    WHEN tc.temp_category = '<36.0' THEN 1
    WHEN tc.temp_category = '36.0-37.9' THEN 2
    WHEN tc.temp_category = '>=38.0' THEN 3
  END;