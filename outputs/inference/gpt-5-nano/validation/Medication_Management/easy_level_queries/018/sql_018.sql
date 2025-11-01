WITH eligible_prescriptions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    (DATETIME_DIFF(pr.stoptime, pr.starttime, SECOND)) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON p.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 82 AND 92
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
)
SELECT
  subject_id,
  hadm_id,
  starttime,
  stoptime,
  drug,
  duration_days
FROM eligible_prescriptions
ORDER BY duration_days DESC
LIMIT 1;