WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE LOWER(p.gender) = 'female'
    AND SAFE_CAST(p.anchor_age AS INT64) >= 60
    AND SAFE_CAST(p.anchor_age AS INT64) <= 70
),

statin_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
  JOIN eligible_patients AS ep
    ON pr.subject_id = ep.subject_id
  WHERE LOWER(pr.drug) LIKE '%atorvastatin%'
    AND pr.dose_val_rx BETWEEN 40 AND 80
    AND LOWER(TRIM(pr.dose_unit_rx)) = 'mg'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
),

quartiles AS (
  SELECT APPROX_QUANTILES(duration_days, 4) AS qs
  FROM statin_prescriptions
)

SELECT
  qs[OFFSET(1)] AS q1_days,
  qs[OFFSET(3)] AS q3_days,
  (qs[OFFSET(3)] - qs[OFFSET(1)]) AS iqr_days
FROM quartiles;