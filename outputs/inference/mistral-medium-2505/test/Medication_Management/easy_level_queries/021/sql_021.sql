WITH female_patients_75_85 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Calculate age at admission (anchor_age is age at anchor_year)
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 75 AND 85
),

atorvastatin_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.dose_val_rx,
    p.starttime,
    p.stoptime,
    -- Calculate duration in days
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    female_patients_75_85 fp
  ON
    p.subject_id = fp.subject_id AND p.hadm_id = fp.hadm_id
  WHERE
    LOWER(p.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND REGEXP_CONTAINS(p.dose_val_rx, r'^[0-9.]+$') -- Ensure dose_val_rx is numeric
)

SELECT
  PERCENTILE_CONT(duration_days, 0.25) OVER() AS q1,
  PERCENTILE_CONT(duration_days, 0.75) OVER() AS q3,
  PERCENTILE_CONT(duration_days, 0.75) OVER() - PERCENTILE_CONT(duration_days, 0.25) OVER() AS iqr
FROM
  atorvastatin_prescriptions
LIMIT 1; -- Since we're calculating percentiles over the entire result set, we only need one row;