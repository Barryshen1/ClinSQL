WITH eligible_prescriptions AS (
  SELECT
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    p.subject_id = pr.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    pr.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND pr.drug = 'Digoxin'
    AND pr.stoptime IS NOT NULL
    AND pr.starttime < pr.stoptime
    AND (
      p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year
    ) BETWEEN 36 AND 46
)

SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] -
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS iqr_duration_days
FROM
  eligible_prescriptions;