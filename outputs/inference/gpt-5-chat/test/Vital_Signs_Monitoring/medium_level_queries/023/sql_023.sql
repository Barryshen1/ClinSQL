WITH aki_flags AS (
  SELECT DISTINCT hadm_id, 1 AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '584%')
     OR (icd_version = 10 AND icd_code LIKE 'N17%')
),
temp_first24h AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    ce.charttime,
    ce.valuenum AS temp_c
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id
   AND icu.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 62 AND 72
    AND di.label LIKE 'Temperature%'
    AND di.unitname LIKE 'Cel%'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
),
categorized AS (
  SELECT
    t.*,
    CASE
      WHEN temp_c < 36.0 THEN '<36.0'
      WHEN temp_c >= 36.0 AND temp_c < 38.0 THEN '36.0–37.9'
      WHEN temp_c >= 38.0 THEN '≥38.0'
    END AS temp_category
  FROM temp_first24h t
),
stats AS (
  SELECT
    temp_category,
    AVG(temp_c) AS mean_temp,
    APPROX_QUANTILES(temp_c, 100)[SAFE_ORDINAL(51)] AS median_temp,
    APPROX_QUANTILES(temp_c, 100)[SAFE_ORDINAL(76)]
      - APPROX_QUANTILES(temp_c, 100)[SAFE_ORDINAL(26)] AS iqr_temp,
    COUNT(*) AS n_measurements,
    COUNT(DISTINCT stay_id) AS n_stays,
    COUNT(DISTINCT CASE WHEN aki_flag = 1 THEN stay_id END) AS aki_stays
  FROM categorized
  LEFT JOIN aki_flags USING (hadm_id)
  GROUP BY temp_category
)
SELECT
  temp_category,
  mean_temp,
  median_temp,
  iqr_temp,
  n_measurements,
  n_stays,
  aki_stays,
  SAFE_DIVIDE(aki_stays, n_stays) AS aki_rate
FROM stats
ORDER BY temp_category;