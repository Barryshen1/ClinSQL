WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 84 AND 94
),
dapt_rx AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.drug,
    pr.starttime,
    pr.stoptime,
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR)/24.0 AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort c
    ON pr.subject_id = c.subject_id
   AND pr.hadm_id = c.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) > 0
    AND (
      LOWER(pr.drug) LIKE '%aspirin%' OR
      LOWER(pr.drug) LIKE '%clopidogrel%' OR
      LOWER(pr.drug) LIKE '%prasugrel%' OR
      LOWER(pr.drug) LIKE '%ticagrelor%'
    )
)
SELECT
  MAX(duration_days) AS max_single_inpatient_dapt_days
FROM dapt_rx;