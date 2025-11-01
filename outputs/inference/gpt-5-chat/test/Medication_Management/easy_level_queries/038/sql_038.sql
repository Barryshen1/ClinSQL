WITH digoxin_rx AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE LOWER(pr.drug) LIKE '%digoxin%'
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS q1_duration_days,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS q3_duration_days
FROM digoxin_rx
WHERE duration_days >= 0
;