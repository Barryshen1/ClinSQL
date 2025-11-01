WITH digoxin_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    DATE_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
    AND p.hadm_id = a.hadm_id
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 66 AND 76
    AND LOWER(p.drug) LIKE '%digoxin%'
    AND p.stoptime IS NOT NULL
    AND p.starttime >= a.admittime
    AND p.stoptime <= a.dischtime
)
SELECT
  AVG(duration_days) AS avg_duration_days
FROM
  digoxin_prescriptions;