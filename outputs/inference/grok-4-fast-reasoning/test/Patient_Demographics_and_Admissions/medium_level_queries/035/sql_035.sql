WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'death'
      WHEN a.discharge_location IN ('DISCHARGED TO HOME', 'DISCHARGED TO HOME WITH HOME IV PROVIDER') THEN 'home'
      ELSE 'facility'
    END AS outcome
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND a.admission_location = 'EMERGENCY ROOM'
    AND a.dischtime IS NOT NULL
)
SELECT 
  outcome,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS q3,
  SAFE_DIVIDE(COUNTIF(los <= 14), COUNT(*)) * 100 AS percentile_14
FROM cohort
GROUP BY outcome
ORDER BY CASE outcome 
  WHEN 'death' THEN 1 
  WHEN 'home' THEN 2 
  ELSE 3 
END;