WITH eligible_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON i.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
),
aki_admissions AS (
  -- Flag hospital admissions with AKI (ICD-9 584* or ICD-10 N17*)
  SELECT
    hadm_id,
    1 AS has_aki
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND icd_code LIKE '584%')
    OR (icd_version = 10 AND icd_code LIKE 'N17%')
  GROUP BY
    hadm_id
),
temps_first24h AS (
  -- Pull all temperature measurements in first 24h of ICU stay
  SELECT
    es.subject_id,
    es.hadm_id,
    es.stay_id,
    ce.valuenum AS temp_c,
    ce.charttime
  FROM
    eligible_stays es
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON es.subject_id = ce.subject_id
      AND es.stay_id = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%temp%'
    AND di.unitname = 'Cel'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN es.intime
      AND TIMESTAMP_ADD(es.intime, INTERVAL 24 HOUR)
),
temps_categorized AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    temp_c,
    CASE
      WHEN temp_c < 36.0 THEN '<36.0'
      WHEN temp_c < 38.0 THEN '36.0–37.9'
      ELSE '≥38.0'
    END AS temp_cat
  FROM
    temps_first24h
),
agg_temps AS (
  -- Aggregate statistics per temperature category
  SELECT
    temps.temp_cat,
    AVG(temps.temp_c) AS mean_temp,
    -- BigQuery APPROX_QUANTILES to get median and IQR
    APPROX_QUANTILES(temps.temp_c, 100)[OFFSET(50)] AS median_temp,
    APPROX_QUANTILES(temps.temp_c, 100)[OFFSET(25)] AS temp_q1,
    APPROX_QUANTILES(temps.temp_c, 100)[OFFSET(75)] AS temp_q3,
    -- Distinct admissions with any measurement in this category
    COUNT(DISTINCT temps.hadm_id) AS total_admissions,
    -- Distinct admissions with AKI and any measurement in this category
    COUNT(DISTINCT 
      CASE WHEN ak.has_aki = 1 THEN temps.hadm_id END
    ) AS admissions_with_aki
  FROM
    temps_categorized AS temps
    LEFT JOIN aki_admissions ak
      ON temps.hadm_id = ak.hadm_id
  GROUP BY
    temps.temp_cat
)
SELECT
  temp_cat AS temperature_category,
  mean_temp,
  median_temp,
  temp_q1 AS iqr_25,
  temp_q3 AS iqr_75,
  SAFE_DIVIDE(admissions_with_aki, total_admissions) AS aki_rate
FROM
  agg_temps
ORDER BY
  CASE temp_cat
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    WHEN '≥38.0' THEN 3
  END;