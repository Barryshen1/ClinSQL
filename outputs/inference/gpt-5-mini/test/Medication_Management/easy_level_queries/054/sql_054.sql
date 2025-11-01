WITH digoxin_rx AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id,
    p.pharmacy_id,
    p.starttime,
    p.stoptime,
    p.drug
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON p.subject_id = pt.subject_id
  WHERE p.hadm_id IS NOT NULL
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
    AND p.stoptime > p.starttime
    AND LOWER(COALESCE(p.drug, '')) LIKE '%digoxin%'
    AND pt.gender = 'M'
    AND pt.anchor_age BETWEEN 66 AND 76
)
SELECT
  AVG(TIMESTAMP_DIFF(stoptime, starttime, SECOND) / 86400.0) AS avg_duration_days,
  COUNT(*) AS n_prescriptions
FROM digoxin_rx;