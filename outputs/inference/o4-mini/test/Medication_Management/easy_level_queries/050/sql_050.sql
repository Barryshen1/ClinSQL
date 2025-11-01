WITH spirono_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.subject_id = a.subject_id
    AND pr.hadm_id    = a.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON pr.subject_id = pt.subject_id
  WHERE
    pt.gender = 'M'
    AND pt.anchor_age BETWEEN 64 AND 74
    AND (
      LOWER(pr.drug) LIKE '%spironolactone%'
      OR LOWER(pr.drug) LIKE '%eplerenone%'
    )
    AND pr.starttime BETWEEN a.admittime AND a.dischtime
    AND pr.stoptime IS NOT NULL
)
SELECT
  AVG(duration_days) AS avg_duration_days
FROM
  spirono_prescriptions
WHERE
  duration_days >= 0;