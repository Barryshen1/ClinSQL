WITH thiazide_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    p.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND LOWER(p.drug) LIKE '%thiazide%'
    AND p.stoptime IS NOT NULL
)

SELECT
  PERCENTILE_CONT(duration_days, 0.75) OVER() - PERCENTILE_CONT(duration_days, 0.25) OVER() AS iqr_days
FROM
  thiazide_prescriptions
LIMIT 1;