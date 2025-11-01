WITH filtered_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admission_type = 'ELECTIVE'
)
SELECT 
  CASE 
    WHEN deathtime IS NOT NULL OR hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
    ELSE 'Discharged Alive'
  END AS outcome,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS percentile_25,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS percentile_75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS percentile_90
FROM 
  filtered_admissions
GROUP BY 
  outcome;