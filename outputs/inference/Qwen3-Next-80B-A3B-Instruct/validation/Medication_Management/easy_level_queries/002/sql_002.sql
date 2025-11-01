WITH amiodarone_prescriptions AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON pr.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) > 0
),
iqr_calc AS (
  SELECT
    PERCENTILE_CONT(duration_days, 0.25) OVER () AS q1,
    PERCENTILE_CONT(duration_days, 0.75) OVER () AS q3
  FROM
    amiodarone_prescriptions
)
SELECT
  q3 - q1 AS iqr_duration_days
FROM
  iqr_calc
LIMIT 1;