WITH eligible_prescriptions AS (
  SELECT 
    TIMESTAMP_DIFF(pr.stoptime, pr.starttime, HOUR) / 24.0 AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
      ON p.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
  WHERE 
    p.gender = 'F'
    AND ( 
      EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age 
    ) BETWEEN 59 AND 69
    AND REGEXP_CONTAINS(LOWER(pr.drug), r'amlodipine|nifedipine|felodipine|isradipine|nicardipine|nisoldipine|nitrendipine')
    AND pr.stoptime IS NOT NULL
    AND pr.stoptime >= pr.starttime
)
SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM eligible_prescriptions;