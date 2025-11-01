WITH ccb_prescriptions AS (
  SELECT
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON pr.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND pr.stoptime IS NOT NULL
    AND pr.drug LIKE '%amlodipine%' OR pr.drug LIKE '%nifedipine%' 
    OR pr.drug LIKE '%felodipine%' OR pr.drug LIKE '%isradipine%' 
    OR pr.drug LIKE '%nicardipine%' OR pr.drug LIKE '%nisoldipine%'
)
SELECT
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS percentile_25_duration_days
FROM ccb_prescriptions
WHERE duration_days >= 0;