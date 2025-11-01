WITH temperature_data AS (
  SELECT
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ce.valuenum AS temperature,
    CASE
      WHEN ce.valuenum < 36.0 THEN 'Low'
      WHEN ce.valuenum >= 36.0 AND ce.valuenum < 38.0 THEN 'Normal'
      WHEN ce.valuenum >= 38.0 THEN 'High'
    END AS temp_category,
    ie.intime
  FROM physionet-data.mimiciv_3_1_icu.icustays ie
  INNER JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON ie.stay_id = ce.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON ie.subject_id = p.subject_id
  WHERE di.label = 'Temperature'
    AND ce.valueuom = 'C'
    AND ce.valuenum IS NOT NULL
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
    AND ce.charttime >= ie.intime
    AND ce.charttime <= TIMESTAMP_ADD(ie.intime, INTERVAL 24 HOUR)
),
aki_flag AS (
  SELECT DISTINCT
    ie.hadm_id,
    CASE 
      WHEN di.icd_code LIKE 'N17%' OR di.icd_code LIKE '584%' THEN 1 
      ELSE 0 
    END AS has_aki
  FROM physionet-data.mimiciv_3_1_icu.icustays ie
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON ie.hadm_id = di.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses ddi
    ON di.icd_code = ddi.icd_code AND di.icd_version = ddi.icd_version
  WHERE di.icd_version IN (9, 10)
    AND (ddi.long_title LIKE '%Acute Kidney Injury%' 
         OR di.icd_code LIKE 'N17%' 
         OR di.icd_code LIKE '584%')
),
agg_stats AS (
  SELECT
    td.temp_category,
    AVG(td.temperature) AS mean_temperature,
    PERCENTILE_DISC(td.temperature, 0.5) AS median_temperature,
    PERCENTILE_DISC(td.temperature, 0.25) AS q1_temperature,
    PERCENTILE_DISC(td.temperature, 0.75) AS q3_temperature,
    COUNT(*) AS n,
    SUM(COALESCE(af.has_aki, 0)) AS aki_count
  FROM temperature_data td
  LEFT JOIN aki_flag af
    ON td.hadm_id = af.hadm_id
  GROUP BY td.temp_category
)
SELECT
  temp_category,
  ROUND(mean_temperature, 2) AS mean,
  ROUND(median_temperature, 2) AS median,
  ROUND(q3_temperature - q1_temperature, 2) AS iqr,
  ROUND(aki_count * 1.0 / n, 4) AS aki_rate
FROM agg_stats
ORDER BY temp_category;