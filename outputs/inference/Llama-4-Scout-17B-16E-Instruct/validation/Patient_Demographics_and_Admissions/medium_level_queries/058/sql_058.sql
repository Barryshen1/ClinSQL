WITH patient_data AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admit_provider_id,
    a.admission_location,
    a.discharge_location,
    a.admission_type,
    p.anchor_age,
    p.gender,
    p.dod,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON a.hadm_id = icu.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type = 'Transfer In'
),
los_data AS (
  SELECT 
    discharge_location,
    los
  FROM (
    SELECT 
      discharge_location,
      icu.los
    FROM 
      patient_data icu
    UNION ALL
    SELECT 
      discharge_location,
      DATEDIFF(a.dischtime, a.admittime) AS los
    FROM 
      patient_data a
    WHERE 
      a.stay_id IS NULL
  ) AS los
)
SELECT 
  discharge_location,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
  SUM(CASE WHEN los = 5 THEN 1 ELSE 0 END) / COUNT(*) AS proportion_5_days
FROM 
  los_data
GROUP BY 
  discharge_location;