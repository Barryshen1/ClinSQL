WITH atorva_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    -- duration in days, with fractional part
    (UNIX_SECONDS(TIMESTAMP(p.stoptime)) - UNIX_SECONDS(TIMESTAMP(p.starttime))) / 86400.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
     AND p.hadm_id    = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
      ON p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'F'
    -- anchor_age is INT64; ensure between 60 and 70
    AND CAST(pt.anchor_age AS INT64) BETWEEN 60 AND 70
    -- ensure prescription falls during the hospitalization
    AND p.starttime >= a.admittime
    AND p.starttime <  a.dischtime
    -- filter atorvastatin 40-80 mg
    AND LOWER(p.drug) LIKE '%atorvastatin%'
    AND CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND LOWER(p.dose_unit_rx) = 'mg'
),
quartiles AS (
  SELECT
    PERCENTILE_CONT(duration_days, 0.25) AS q1,
    PERCENTILE_CONT(duration_days, 0.75) AS q3
  FROM
    atorva_prescriptions
)
SELECT
  q1,
  q3,
  q3 - q1 AS iqr_days
FROM
  quartiles;