with LOS <= 7 days
WITH 
  admissions_filtered AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      DATE_DIFF(a.dischtime, a.admittime) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 52 AND 62
      AND a.admission_type != 'EMERGENCY'
  )

SELECT 
  hospital_expire_flag,
  APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS p50,
  APPROX_QUANTILES(los, 1000)[OFFSET(750)] AS p75,
  APPROX_QUANTILES(los, 1000)[OFFSET(900)] AS p90,
  APPROX_QUANTILES(los, 1000)[OFFSET(950)] AS p95,
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN los <= 7 THEN 1 ELSE 0 END) / COUNT(*) AS proportion_7_days
FROM 
  admissions_filtered
GROUP BY 
  hospital_expire_flag;