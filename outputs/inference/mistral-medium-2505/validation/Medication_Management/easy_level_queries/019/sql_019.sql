WITH heparin_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    p.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 58 AND 68
    AND (LOWER(p.drug) LIKE '%heparin%' OR LOWER(p.drug) LIKE '%enoxaparin%')
    AND p.stoptime IS NOT NULL  -- Exclude ongoing prescriptions
)

SELECT
  PERCENTILE_CONT(duration_days, 0.5) OVER() AS median_duration_days
FROM
  heparin_prescriptions
LIMIT 1;