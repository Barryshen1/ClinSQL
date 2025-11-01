SELECT
  AVG(DATETIME_DIFF(stoptime, starttime, HOUR) / 24.0) AS avg_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON pres.subject_id = pat.subject_id
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 64 AND 74
  AND (LOWER(pres.drug) LIKE '%spironolactone%'
       OR LOWER(pres.drug) LIKE '%eplerenone%')
  AND pres.stoptime IS NOT NULL
  AND pres.starttime IS NOT NULL
  AND pres.stoptime > pres.starttime;