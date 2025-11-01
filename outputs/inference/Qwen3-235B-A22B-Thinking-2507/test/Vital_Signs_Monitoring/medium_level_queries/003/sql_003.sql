WITH filtered_stays AS (
  SELECT 
    icu.stay_id,
    icu.hadm_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM icu.intime) - (p.anchor_year - p.anchor_age) BETWEEN 71 AND 81
),
temperature_data AS (
  SELECT 
    ce.stay_id,
    AVG(ce.valuenum) AS avg_temp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN filtered_stays fs
    ON ce.stay_id = fs.stay_id
  WHERE ce.itemid = 223761  -- Temperature Celsius
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN fs.intime AND DATETIME_ADD(fs.intime, INTERVAL 48 HOUR)
  GROUP BY ce.stay_id
),
mi_diagnoses AS (
  SELECT 
    hadm_id,
    1 AS has_mi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '410%')
    OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
  GROUP BY hadm_id
),
categorized_stays AS (
  SELECT 
    fs.stay_id,
    td.avg_temp,
    CASE 
      WHEN td.avg_temp < 36.0 THEN '<36.0'
      WHEN td.avg_temp BETWEEN 36.0 AND 37.9 THEN '36.0-37.9'
      ELSE '>=38.0'
    END AS temp_category,
    COALESCE(md.has_mi, 0) AS has_mi
  FROM filtered_stays fs
  INNER JOIN temperature_data td
    ON fs.stay_id = td.stay_id
  LEFT JOIN mi_diagnoses md
    ON fs.hadm_id = md.hadm_id
)
SELECT 
  temp_category,
  AVG(avg_temp) AS mean_avg_temp,
  APPROX_QUANTILES(avg_temp, 1000)[OFFSET(500)] AS median_avg_temp,
  APPROX_QUANTILES(avg_temp, 1000)[OFFSET(750)] 
    - APPROX_QUANTILES(avg_temp, 1000)[OFFSET(250)] AS iqr_avg_temp,
  SUM(has_mi) / COUNT(*) AS mi_rate
FROM categorized_stays
GROUP BY temp_category
ORDER BY 
  CASE temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0-37.9' THEN 2
    ELSE 3
  END;