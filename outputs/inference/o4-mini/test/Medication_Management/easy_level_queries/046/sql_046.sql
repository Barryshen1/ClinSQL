WITH filtered_prescriptions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON pr.subject_id = a.subject_id
     AND pr.hadm_id   = a.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND pr.drug IS NOT NULL
    AND (
      LOWER(pr.drug) LIKE '%spironolactone%'
      OR LOWER(pr.drug) LIKE '%eplerenone%'
    )
    AND pr.starttime IS NOT NULL
    AND pr.stoptime  IS NOT NULL
    AND DATE(pr.stoptime) > DATE(pr.starttime)
)
SELECT
  -- median duration in days
  APPROX_QUANTILES(duration_days, 2)[OFFSET(1)] AS median_duration_days
FROM
  filtered_prescriptions;