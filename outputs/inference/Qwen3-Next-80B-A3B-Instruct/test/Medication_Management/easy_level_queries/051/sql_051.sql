WITH digoxin_prescriptions AS (
  SELECT
    p.anchor_age,
    p.gender,
    pr.starttime,
    pr.stoptime,
    EXTRACT(DAY FROM (pr.stoptime - pr.starttime)) AS duration_days
  FROM
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON pr.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
),
iqr_calc AS (
  SELECT
    PERCENTILE_CONT(duration_days, 0.25) OVER () AS q1,
    PERCENTILE_CONT(duration_days, 0.75) OVER () AS q3
  FROM
    digoxin_prescriptions
)
SELECT
  DISTINCT q3 - q1 AS iqr_duration_days
FROM
  iqr_calc;