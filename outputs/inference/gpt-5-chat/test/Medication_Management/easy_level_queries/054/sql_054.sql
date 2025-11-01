WITH digoxin_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON pr.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 66 AND 76
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND DATETIME_DIFF(pr.stoptime, pr.starttime, SECOND) > 0
)
SELECT
  AVG(duration_days) AS avg_duration_days
FROM
  digoxin_prescriptions;