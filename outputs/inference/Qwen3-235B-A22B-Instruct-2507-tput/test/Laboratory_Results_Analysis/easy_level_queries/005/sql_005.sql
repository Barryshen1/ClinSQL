WITH sodium_first AS (
  SELECT
    le.hadm_id,
    MIN(le.charttime) AS first_sodium_time
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON le.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON le.hadm_id = icu.hadm_id
  WHERE dl.label = 'Sodium'
    AND LOWER(dl.fluid) = 'blood'
    AND p.gender = 'M'
    AND le.valuenum IS NOT NULL
  GROUP BY le.hadm_id
),
first_sodium_values AS (
  SELECT
    le.valuenum AS sodium_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN sodium_first sf
    ON le.hadm_id = sf.hadm_id AND le.charttime = sf.first_sodium_time
)
SELECT
  APPROX_QUANTILES(sodium_value, 1000)[OFFSET(750)] -
  APPROX_QUANTILES(sodium_value, 1000)[OFFSET(250)] AS iqr_first_sodium
FROM first_sodium_values;