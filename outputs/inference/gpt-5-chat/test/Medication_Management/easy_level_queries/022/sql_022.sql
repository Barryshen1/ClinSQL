WITH ccb_prescriptions AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(DATE(pr.stoptime), DATE(pr.starttime), DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON p.subject_id = pr.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND (
      LOWER(pr.drug) LIKE '%amlodipine%'
      OR LOWER(pr.drug) LIKE '%felodipine%'
      OR LOWER(pr.drug) LIKE '%isradipine%'
      OR LOWER(pr.drug) LIKE '%nicardipine%'
      OR LOWER(pr.drug) LIKE '%nifedipine%'
      OR LOWER(pr.drug) LIKE '%nimodipine%'
      OR LOWER(pr.drug) LIKE '%nisoldipine%'
    )
)
SELECT
  APPROX_QUANTILES(duration_days, 2)[OFFSET(1)] AS median_duration_days
FROM ccb_prescriptions;