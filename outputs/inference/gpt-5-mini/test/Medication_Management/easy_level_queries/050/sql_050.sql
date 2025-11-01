WITH target_prescriptions AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    LOWER(COALESCE(pr.drug, '')) AS drug,
    pr.starttime,
    pr.stoptime,
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) / 86400.0 AS duration_days,
    CASE
      WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%spironolactone%' THEN 'spironolactone'
      WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%eplerenone%' THEN 'eplerenone'
      ELSE 'other'
    END AS drug_group
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON pr.subject_id = a.subject_id
   AND pr.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    -- Restrict to inpatient prescriptions started during the admission
    AND pr.starttime IS NOT NULL
    AND pr.starttime >= a.admittime
    AND pr.starttime <= a.dischtime
    -- Require a non-null stop time so we can measure duration
    AND pr.stoptime IS NOT NULL
    -- Filter to drugs of interest
    AND (
      LOWER(COALESCE(pr.drug, '')) LIKE '%spironolactone%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%eplerenone%'
    )
    -- Positive duration only
    AND TIMESTAMP_DIFF(pr.stoptime, pr.starttime, SECOND) > 0
)

SELECT
  COUNT(*) AS n_prescriptions,
  ROUND(AVG(duration_days), 3) AS avg_duration_days_overall,
  ROUND(COALESCE(AVG(CASE WHEN drug_group = 'spironolactone' THEN duration_days END), 0), 3) AS avg_duration_days_spironolactone,
  ROUND(COALESCE(AVG(CASE WHEN drug_group = 'eplerenone' THEN duration_days END), 0), 3) AS avg_duration_days_eplerenone
FROM target_prescriptions;