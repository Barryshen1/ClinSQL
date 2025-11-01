WITH durations AS (
  SELECT
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 60 AND 70
    AND LOWER(p.drug) LIKE '%atorvastatin%'
    AND LOWER(p.dose_unit_rx) = 'mg'
    AND SAFE_CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
)
SELECT
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY duration_days) -
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_days) AS iqr
FROM durations;