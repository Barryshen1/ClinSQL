WITH digoxin_prescriptions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.hadm_id = pr.hadm_id
    AND p.subject_id = pr.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime > pr.starttime
),
quartiles AS (
  SELECT
    APPROX_QUANTILES(duration_days, 4) AS quartiles
  FROM digoxin_prescriptions
)
SELECT
  IF(ARRAY_LENGTH(quartiles) >= 4, quartiles[OFFSET(1)], NULL) AS p25,
  IF(ARRAY_LENGTH(quartiles) >= 4, quartiles[OFFSET(3)], NULL) AS p75,
  IF(ARRAY_LENGTH(quartiles) >= 4, quartiles[OFFSET(3)] - quartiles[OFFSET(1)], NULL) AS iqr
FROM quartiles;