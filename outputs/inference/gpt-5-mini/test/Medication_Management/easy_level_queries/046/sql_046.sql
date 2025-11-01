WITH target_prescriptions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    pr.starttime,
    pr.stoptime,
    -- duration in fractional days
    SAFE_DIVIDE(TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND), 86400.0) AS duration_days,
    LOWER(COALESCE(pr.drug, '')) AS drug_lower
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.subject_id = a.subject_id
    AND pr.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    -- ensure prescription has start and stop and is within the admission window
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.starttime <= pr.stoptime
    AND pr.starttime BETWEEN a.admittime AND a.dischtime
    -- match spironolactone or eplerenone (case-insensitive)
    AND (
      LOWER(COALESCE(pr.drug, '')) LIKE '%spironolactone%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%eplerenone%'
    )
)
SELECT
  COUNT(*) AS num_prescriptions,
  -- approximate median (50th percentile) using APPROX_QUANTILES
  ROUND(IFNULL(APPROX_QUANTILES(duration_days, 100)[OFFSET(50)], 0), 3) AS median_duration_days,
  ROUND(AVG(duration_days), 3) AS mean_duration_days
FROM target_prescriptions;