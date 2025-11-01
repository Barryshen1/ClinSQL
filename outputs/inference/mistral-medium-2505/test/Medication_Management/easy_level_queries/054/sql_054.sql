WITH digoxin_prescriptions AS (
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
  WHERE
    LOWER(p.drug) = 'digoxin'
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 66 AND 76
    AND p.stoptime IS NOT NULL
)

SELECT
  AVG(duration_days) AS avg_duration_days
FROM
  digoxin_prescriptions;