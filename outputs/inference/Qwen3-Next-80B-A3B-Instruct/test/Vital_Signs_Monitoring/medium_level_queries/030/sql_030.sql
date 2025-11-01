WITH temperature_first_24h AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.intime,
    AVG(c.valuenum) AS mean_temp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE d.label = 'Temperature'
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 30 AND 42  -- reasonable physiological range
    AND c.charttime >= i.intime
    AND c.charttime < i.intime + INTERVAL '24 hours'
  GROUP BY i.stay_id, i.hadm_id, i.intime
),
mi_diagnoses AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE dd.long_title LIKE '%Myocardial Infarction%'
     OR d.icd_code LIKE '410%'  -- ICD-9
     OR d.icd_code LIKE 'I21%'  -- ICD-10
     OR d.icd_code LIKE 'I22%'  -- ICD-10
),
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 81 AND 91
),
final_data AS (
  SELECT 
    t.stay_id,
    t.mean_temp,
    CASE 
      WHEN t.mean_temp < 36.0 THEN '<36.0'
      WHEN t.mean_temp >= 36.0 AND t.mean_temp < 38.0 THEN '36.0-37.9'
      WHEN t.mean_temp >= 38.0 THEN '>=38.0'
    END AS temp_category,
    CASE WHEN mi.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS mi_flag
  FROM temperature_first_24h t
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON t.hadm_id = a.hadm_id
  INNER JOIN filtered_patients p
    ON a.subject_id = p.subject_id
  LEFT JOIN mi_diagnoses mi
    ON t.hadm_id = mi.hadm_id
)
SELECT 
  temp_category,
  COUNT(*) AS N,
  AVG(mean_temp) AS mean,
  PERCENTILE_CONT(mean_temp, 0.5) AS median,
  PERCENTILE_CONT(mean_temp, 0.25) AS q1,
  PERCENTILE_CONT(mean_temp, 0.75) AS q3,
  AVG(mi_flag) * 100 AS mi_rate_percent
FROM final_data
GROUP BY temp_category
ORDER BY temp_category;