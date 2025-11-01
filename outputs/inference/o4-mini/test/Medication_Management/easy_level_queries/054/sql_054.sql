SELECT
  ROUND(AVG(duration_days), 2) AS avg_digoxin_duration_days
FROM (
  SELECT
    p.subject_id,
    p.hadm_id,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pt
  ON
    p.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 66 AND 76
    AND LOWER(p.drug) LIKE '%digoxin%'
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
) AS durations;