WITH heart_rates AS (
  SELECT 
    ce.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id 
    AND icu.hadm_id = ce.hadm_id 
    AND icu.stay_id = ce.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 45 AND 55
    AND icu.los >= 2
    AND LOWER(di.label) LIKE '%heart rate%'
    AND ce.valuenum BETWEEN 0 AND 300
    AND SAFE_DIVIDE(TIMESTAMP_DIFF(ce.charttime, icu.intime, SECOND), 3600.0) >= 24
),
quantiles AS (
  SELECT 
    APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3
  FROM heart_rates
)
SELECT 
  q1,
  q3,
  q3 - q1 AS iqr
FROM quantiles;