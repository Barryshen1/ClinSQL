WITH arb_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    -- duration in fractional days (seconds -> days)
    TIMESTAMP_DIFF(CAST(p.stoptime AS TIMESTAMP), CAST(p.starttime AS TIMESTAMP), SECOND) / 86400.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
   AND p.hadm_id = a.hadm_id
  WHERE pt.gender = 'F'
    AND pt.anchor_age BETWEEN 77 AND 87
    AND p.hadm_id IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND CAST(p.stoptime AS TIMESTAMP) > CAST(p.starttime AS TIMESTAMP)
    -- ensure the prescription started during the hospital admission
    AND CAST(p.starttime AS TIMESTAMP) BETWEEN CAST(a.admittime AS TIMESTAMP) AND CAST(a.dischtime AS TIMESTAMP)
    -- match common ARB drug names (case-insensitive)
    AND (
      LOWER(COALESCE(p.drug, '')) LIKE '%losartan%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%valsartan%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%candesartan%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%irbesartan%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%telmisartan%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%olmesartan%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%eprosartan%'
      OR LOWER(COALESCE(p.drug, '')) LIKE '%azilsartan%'
    )
)

SELECT
  ROUND(AVG(duration_days), 2) AS avg_duration_days,
  COUNT(*) AS n_prescriptions
FROM arb_prescriptions;