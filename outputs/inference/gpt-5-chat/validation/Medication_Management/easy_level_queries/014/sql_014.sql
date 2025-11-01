WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
),
high_intensity AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    SAFE_CAST(pr.dose_val_rx AS FLOAT64) AS dose_mg,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort c
    ON pr.subject_id = c.subject_id
    AND pr.hadm_id = c.hadm_id
  WHERE LOWER(pr.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(pr.dose_val_rx AS FLOAT64) IN (40, 80)
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
)
SELECT
  MIN(duration_days) AS min_duration_days
FROM high_intensity;