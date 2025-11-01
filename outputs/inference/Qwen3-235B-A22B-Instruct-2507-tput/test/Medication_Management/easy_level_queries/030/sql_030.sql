SELECT
  APPROX_QUANTILE(duration_hours, 100)[OFFSET(25)] AS percentile_25_duration_hours
FROM (
  SELECT
    DATETIME_DIFF(pres.stoptime, pres.starttime, HOUR) AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients pat
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.prescriptions pres
  ON
    pat.subject_id = pres.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 42 AND 52
    AND LOWER(pres.drug) LIKE '%amiodarone%'
    AND pres.hadm_id IS NOT NULL
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND pres.starttime < pres.stoptime
);