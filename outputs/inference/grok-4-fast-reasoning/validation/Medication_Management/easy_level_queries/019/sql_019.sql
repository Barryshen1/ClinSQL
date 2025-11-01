WITH cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 58 AND 68
),
prescription_durations AS (
  SELECT 
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN cohort c ON pr.subject_id = c.subject_id
  WHERE pr.hadm_id IS NOT NULL
    AND pr.stoptime IS NOT NULL
    AND pr.starttime < pr.stoptime  -- Ensure valid positive duration
    AND (UPPER(pr.drug) LIKE '%HEPARIN%' OR UPPER(pr.drug) LIKE '%ENOXAPARIN%')
)
SELECT 
  APPROX_QUANTILES(duration_days, 2)[OFFSET(1)] AS median_duration_days
FROM prescription_durations
WHERE duration_days > 0;