SELECT
  AVG(duration_days) AS avg_digoxin_prescription_duration_days
FROM (
  SELECT
    DATE_DIFF(DATE(pres.starttime), DATE(pres.stoptime), DAY) * -1 AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON pres.subject_id = pat.subject_id
  WHERE
    LOWER(pres.drug) LIKE '%digoxin%'
    AND pat.gender = 'M'
    AND pat.anchor_age BETWEEN 66 AND 76
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
)
WHERE
  duration_days > 0;