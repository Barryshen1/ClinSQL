WITH digoxin_prescriptions AS (
  SELECT
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.stoptime IS NOT NULL
    AND pr.starttime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(duration_days, 100) [OFFSET(25)] AS q25,
  APPROX_QUANTILES(duration_days, 100) [OFFSET(75)] AS q75
FROM digoxin_prescriptions;