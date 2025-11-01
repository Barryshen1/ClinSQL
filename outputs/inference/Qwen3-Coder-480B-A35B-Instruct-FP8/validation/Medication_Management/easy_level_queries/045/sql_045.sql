WITH patient_prescriptions AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    pr.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND pr.drug IS NOT NULL
    AND LOWER(pr.drug) LIKE '%dapt%'
    AND pr.hadm_id IS NOT NULL
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
),
quartiles AS (
  SELECT
    APPROX_QUANTILES(duration_hours, 4) AS q
  FROM
    patient_prescriptions
)
SELECT
  q[OFFSET(3)] - q[OFFSET(1)] AS iqr_duration_hours
FROM
  quartiles;