WITH temp_first_48h AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    AVG(ce.valuenum) AS avg_temp_48h
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON i.stay_id = ce.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND LOWER(di.label) LIKE '%temperature%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= i.intime + INTERVAL '48' HOUR
  GROUP BY i.stay_id, i.hadm_id, i.intime
),
mi_flag AS (
  SELECT DISTINCT
    di.hadm_id,
    1 AS mi_flag
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE 
    (di.icd_version = 9 AND di.icd_code LIKE '410%')
    OR (di.icd_version = 10 AND di.icd_code LIKE 'I21%')
    OR (di.icd_version = 10 AND di.icd_code LIKE 'I22%')
),
temp_with_mi AS (
  SELECT 
    t.stay_id,
    t.avg_temp_48h,
    COALESCE(m.mi_flag, 0) AS mi_flag,
    CASE 
      WHEN t.avg_temp_48h < 36.0 THEN '<36.0'
      WHEN t.avg_temp_48h >= 36.0 AND t.avg_temp_48h < 38.0 THEN '36.0–37.9'
      WHEN t.avg_temp_48h >= 38.0 THEN '≥38.0'
    END AS temp_category
  FROM temp_first_48h t
  LEFT JOIN mi_flag m ON t.hadm_id = m.hadm_id
)
SELECT 
  temp_category,
  AVG(avg_temp_48h) AS mean_temp,
  APPROX_QUANTILES(avg_temp_48h, 100)[OFFSET(50)] AS median_temp,
  APPROX_QUANTILES(avg_temp_48h, 100)[OFFSET(75)] - APPROX_QUANTILES(avg_temp_48h, 100)[OFFSET(25)] AS iqr_temp,
  AVG(CAST(mi_flag AS FLOAT64)) AS mi_rate
FROM temp_with_mi
WHERE temp_category IS NOT NULL
GROUP BY temp_category
ORDER BY temp_category;