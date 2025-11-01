WITH atorv_prescriptions AS (
  SELECT
    rx.subject_id,
    rx.hadm_id,
    rx.starttime,
    rx.stoptime,
    -- duration in days (integer)
    TIMESTAMP_DIFF(rx.stoptime, rx.starttime, DAY) AS duration_days,
    rx.drug,
    rx.dose_val_rx,
    rx.dose_unit_rx,
    rx.prod_strength
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON rx.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON rx.subject_id = p.subject_id
  WHERE
    -- female patients aged 60-70 (inclusive)
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70

    -- drug name contains atorvastatin
    AND LOWER(COALESCE(rx.drug, '')) LIKE '%atorvastatin%'

    -- require valid start and stop times, and positive duration
    AND rx.starttime IS NOT NULL
    AND rx.stoptime IS NOT NULL
    AND rx.stoptime > rx.starttime

    -- dose between 40 and 80 mg, either from dose_val_rx + unit, or from prod_strength containing 'mg'
    AND (
      -- explicit numeric dose value with mg unit (cast to float)
      (SAFE_CAST(rx.dose_val_rx AS FLOAT64) IS NOT NULL
       AND LOWER(COALESCE(rx.dose_unit_rx, '')) IN ('mg', 'milligram', 'milligrams')
       AND SAFE_CAST(rx.dose_val_rx AS FLOAT64) BETWEEN 40.0 AND 80.0)
      OR
      -- numeric in prod_strength like '40 mg'
      (rx.prod_strength IS NOT NULL
       AND REGEXP_CONTAINS(LOWER(rx.prod_strength), r'\d+(\.\d+)?\s*mg')
       AND SAFE_CAST(REGEXP_EXTRACT(rx.prod_strength, r'(\d+(\.\d+)?)') AS FLOAT64) BETWEEN 40.0 AND 80.0)
      OR
      -- fallback: dose_val_rx present without unit but numeric in the 40-80 range
      (SAFE_CAST(rx.dose_val_rx AS FLOAT64) IS NOT NULL
       AND (rx.dose_unit_rx IS NULL OR TRIM(rx.dose_unit_rx) = '')
       AND SAFE_CAST(rx.dose_val_rx AS FLOAT64) BETWEEN 40.0 AND 80.0)
    )
),

quantiles AS (
  -- compute approximate percentiles (0..100). APPROX_QUANTILES returns array[0..100].
  SELECT APPROX_QUANTILES(duration_days, 100) AS q_arr
  FROM atorv_prescriptions
),

stats AS (
  SELECT
    COUNT(*) AS total_prescriptions,
    COUNT(DISTINCT subject_id) AS unique_patients
  FROM atorv_prescriptions
)

SELECT
  q_arr[OFFSET(25)] AS p25_days,
  q_arr[OFFSET(75)] AS p75_days,
  SAFE_CAST(q_arr[OFFSET(75)] - q_arr[OFFSET(25)] AS FLOAT64) AS iqr_days,
  stats.total_prescriptions,
  stats.unique_patients
FROM quantiles
CROSS JOIN stats;