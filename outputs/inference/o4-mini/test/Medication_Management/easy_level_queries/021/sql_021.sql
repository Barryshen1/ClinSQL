WITH atorva_durations AS (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
     AND p.hadm_id     = a.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
      ON p.subject_id = pt.subject_id
  WHERE
    LOWER(p.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND UPPER(p.dose_unit_rx) = 'MG'
    AND pt.gender = 'F'
    AND pt.anchor_age BETWEEN 75 AND 85
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
)
SELECT
  quants[OFFSET(1)] AS q1_duration_days,  -- 25th percentile
  quants[OFFSET(3)] AS q3_duration_days   -- 75th percentile
FROM (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quants
  FROM
    atorva_durations
);