WITH stays AS (
  SELECT 
    i.stay_id, 
    i.subject_id, 
    i.hadm_id, 
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),
mi_hadms AS (
  SELECT 
    hadm_id, 
    1 AS has_mi
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '410%')
     OR (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
  GROUP BY hadm_id
),
temp_measures AS (
  SELECT 
    s.stay_id,
    s.hadm_id,
    COALESCE(m.has_mi, 0) AS has_mi,
    AVG(
      CASE 
        WHEN c.itemid IN (677, 223761) THEN (c.valuenum - 32) * 5.0 / 9.0
        WHEN c.itemid IN (676, 223762) THEN c.valuenum
        ELSE NULL 
      END
    ) AS mean_temp
  FROM stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON c.stay_id = s.stay_id
    AND c.charttime >= s.intime
    AND c.charttime < DATETIME_ADD(s.intime, INTERVAL 1 DAY)
    AND c.itemid IN (676, 677, 223761, 223762)
    AND c.valuenum IS NOT NULL
  LEFT JOIN mi_hadms m 
    ON s.hadm_id = m.hadm_id
  GROUP BY s.stay_id, s.hadm_id, has_mi
  HAVING COUNT(c.itemid) > 0
)
SELECT 
  CASE 
    WHEN mean_temp < 36.0 THEN '<36.0'
    WHEN mean_temp < 38.0 THEN '36.0-37.9'
    ELSE '>=38.0'
  END AS temp_category,
  COUNT(*) AS N,
  ROUND(AVG(mean_temp), 2) AS mean,
  ROUND(APPROX_QUANTILES(mean_temp, 2)[OFFSET(1)], 2) AS median,
  ROUND(APPROX_QUANTILES(mean_temp, 4)[OFFSET(0)], 2) AS iqr_25th,
  ROUND(APPROX_QUANTILES(mean_temp, 4)[OFFSET(3)], 2) AS iqr_75th,
  ROUND(AVG(has_mi) * 100, 2) AS mi_rate_pct
FROM temp_measures
GROUP BY temp_category
ORDER BY 
  CASE temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0-37.9' THEN 2
    ELSE 3
  END;