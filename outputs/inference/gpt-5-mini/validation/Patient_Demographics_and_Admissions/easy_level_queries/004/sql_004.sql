WITH first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- compute LOS in days as a floating point number (may be fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 70 AND 80
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  STDDEV_SAMP(los_days) AS sd_los_days,
  COUNT(1) AS n_patients,
  AVG(los_days) AS mean_los_days
FROM
  first_admissions
WHERE
  rn = 1;