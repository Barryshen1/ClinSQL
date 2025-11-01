SELECT
  STDDEV(duration_days) AS sd_duration_days
FROM (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.drug,
    DATETIME_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    pr.hadm_id = a.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 73 AND 83
    AND LOWER(pr.drug) LIKE '%nitrate%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.starttime < pr.stoptime
) sub;