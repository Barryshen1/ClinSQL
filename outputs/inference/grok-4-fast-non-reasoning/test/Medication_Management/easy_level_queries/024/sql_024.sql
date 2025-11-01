WITH eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
    AND a.admission_type IN ('ELECTIVE', 'URGENT', 'EMERGENCY')
),
dapt_prescriptions AS (
  SELECT 
    pres.subject_id,
    pres.hadm_id,
    pres.pharmacy_id,
    TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
  INNER JOIN eligible_patients ep
    ON pres.subject_id = ep.subject_id
  WHERE pres.hadm_id IS NOT NULL  -- Ensure hospital admission context
    AND LOWER(pres.drug) LIKE '%aspirin%'
      OR LOWER(pres.drug) LIKE '%clopidogrel%'
      OR LOWER(pres.drug) LIKE '%prasugrel%'
      OR LOWER(pres.drug) LIKE '%ticagrelor%'
    AND pres.starttime IS NOT NULL
    AND pres.stoptime IS NOT NULL
    AND TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) > 0
)
SELECT MAX(duration_days) AS max_single_dapt_duration_days
FROM dapt_prescriptions;