WITH patient_data AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.discharge_location,
    a.hospital_expire_flag,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    DATETIME_DIFF(icu.outtime, icu.intime, HOUR) / 24 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
),
discharge_disposition AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    los_days,
    CASE
      WHEN discharge_location = 'HOME' THEN 'Home'
      WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB', 'OTHER FACILITY') THEN 'Facility'
      ELSE 'Other'
    END AS discharge_category,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital Death'
      ELSE 
        CASE
          WHEN discharge_location = 'HOME' THEN 'Home'
          WHEN discharge_location IN ('SKILLED NURSING FACILITY', 'REHAB', 'OTHER FACILITY') THEN 'Facility'
          ELSE 'Other'
        END
    END AS discharge_status
  FROM 
    patient_data
)
SELECT 
  discharge_status,
  COUNT(*) AS count,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los
FROM 
  discharge_disposition
WHERE 
  discharge_status IN ('Home', 'Facility', 'In-hospital Death')
GROUP BY 
  discharge_status
ORDER BY 
  discharge_status;