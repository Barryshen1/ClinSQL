WITH durations AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON p.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
     AND p.hadm_id    = a.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 58 AND 68
    AND (
      LOWER(p.drug) LIKE '%heparin%'
      OR LOWER(p.drug) LIKE '%enoxaparin%'
    )
    AND p.starttime IS NOT NULL
    AND p.stoptime  IS NOT NULL
)

SELECT
  -- approximate median (50th percentile) of the durations
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM
  durations;