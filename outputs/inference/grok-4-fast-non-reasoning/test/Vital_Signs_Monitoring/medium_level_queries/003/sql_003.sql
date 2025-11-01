WITH temp_data AS (
  -- First 48h temperatures per stay
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.los,
    AVG(ce.valuenum) AS avg_temp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` c
  INNER JOIN `physionet-data.mimiciv_3_1_patients` p
    ON c.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.subject_id = ce.subject_id
    AND c.hadm_id = ce.hadm_id
    AND c.stay_id = ce.stay_id
    AND ce.itemid IN (676, 677, 678, 679, 223761, 223762)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 20 AND 45  -- Reasonable temp range
    AND ce.charttime >= c.intime
    AND ce.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND c.los >= 2  -- Full 48h stays only
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.intime, c.los
  HAVING COUNT(ce.valuenum) > 0  -- Stays with at least one temp
),
mi_data AS (
  -- Admission-level MI flag
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id,
    1 AS has_mi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE d.icd_code LIKE '410%'
    AND d.icd_version = '9'  -- ICD-9 for MI codes
),
categorized_stays AS (
  SELECT 
    t.*,
    CASE 
      WHEN t.avg_temp < 36.0 THEN '<36.0'
      WHEN t.avg_temp >= 36.0 AND t.avg_temp <= 37.9 THEN '36.0–37.9'
      ELSE '>=38.0'
    END AS temp_category,
    COALESCE(m.has_mi, 0) AS has_mi
  FROM temp_data t
  LEFT JOIN mi_data m
    ON t.subject_id = m.subject_id
    AND t.hadm_id = m.hadm_id
)
SELECT 
  temp_category,
  COUNT(stay_id) AS n_stays,
  ROUND(AVG(avg_temp), 2) AS mean_temp,
  ROUND(PERCENTILE_CONT(avg_temp, 0.5) OVER (PARTITION BY temp_category), 2) AS median_temp,
  ROUND(PERCENTILE_CONT(avg_temp, 0.25) OVER (PARTITION BY temp_category), 2) AS q1_temp,
  ROUND(PERCENTILE_CONT(avg_temp, 0.75) OVER (PARTITION BY temp_category), 2) AS q3_temp,
  ROUND(SUM(has_mi) * 100.0 / COUNT(stay_id), 2) AS mi_rate_percent
FROM categorized_stays
GROUP BY temp_category
ORDER BY 
  CASE temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    ELSE 3
  END;