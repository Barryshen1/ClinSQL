WITH amio_rx AS (
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON a.subject_id = pr.subject_id
    AND a.hadm_id = pr.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND LOWER(pr.drug) LIKE '%amiodarone%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
)
SELECT
  ROUND(PERCENTILE_CONT(duration_days, 0.75) OVER() -
        PERCENTILE_CONT(duration_days, 0.25) OVER(), 2) AS iqr_duration_days
FROM amio_rx
LIMIT 1;