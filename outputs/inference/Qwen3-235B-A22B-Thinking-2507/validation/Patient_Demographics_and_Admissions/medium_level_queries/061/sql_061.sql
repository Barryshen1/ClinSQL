WITH filtered AS (
  SELECT
    admissions.hadm_id,
    patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year) AS age,
    TIMESTAMP_DIFF(admissions.dischtime, admissions.admittime, SECOND) / 86400.0 AS los,
    CASE 
      WHEN admissions.hospital_expire_flag = 1 THEN 'death'
      WHEN admissions.discharge_location IN ('HOME', 'HOME HEALTH CARE') THEN 'home'
      ELSE 'facility'
    END AS outcome
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` admissions
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON admissions.subject_id = patients.subject_id
  WHERE 
    patients.gender = 'M'
    AND admissions.dischtime IS NOT NULL
    AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 86 AND 96
)
SELECT
  outcome,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(500)] AS median_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(750)] AS p75_los,
  APPROX_QUANTILES(los, 1000)[OFFSET(900)] AS p90_los,
  (COUNTIF(los >= 10.0) * 100.0) / COUNT(*) AS pct_10day
FROM filtered
GROUP BY outcome
ORDER BY 
  CASE outcome
    WHEN 'home' THEN 1
    WHEN 'facility' THEN 2
    WHEN 'death' THEN 3
  END;