WITH patient_data AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.discharge_location,
    a.hospital_expire_flag,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    DATETIME_DIFF(icu.outtime, icu.intime, HOUR) / 24 AS los
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON icu.hadm_id = a.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' AND p.anchor_age BETWEEN 40 AND 50
),
discharge_outcome AS (
  SELECT 
    los,
    CASE
      WHEN discharge_location = 'HOME' THEN 'home'
      WHEN discharge_location LIKE '%HOSPICE%' THEN 'hospice'
      WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
      ELSE 'other'
    END AS discharge_category
  FROM 
    patient_data
)
SELECT 
  discharge_category,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95_los,
  AVG(IF(los <= 7, 1, 0)) * 100 AS percent_le_7_days
FROM 
  discharge_outcome
WHERE 
  discharge_category IN ('home', 'hospice', 'in-hospital death')
GROUP BY 
  discharge_category;