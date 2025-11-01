SELECT
  STDDEV_SAMP(duration_days) AS stddev_ace_duration_days
FROM (
  SELECT
    p.subject_id,
    pr.hadm_id,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON
    a.hadm_id = pr.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(pr.drug) LIKE '%ace%'
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
) AS ace_durations;