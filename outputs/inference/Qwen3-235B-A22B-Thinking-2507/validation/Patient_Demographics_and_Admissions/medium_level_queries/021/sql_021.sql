WITH admissions_with_age AS (
  SELECT 
    a.*,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
first_service AS (
  SELECT 
    hadm_id,
    curr_service,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY transfertime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.services`
),
surgical_admissions AS (
  SELECT hadm_id
  FROM first_service
  WHERE rn = 1
    AND curr_service IN ('SURG', 'ORTHO', 'ENT', 'URO', 'VSURG', 'NSURG', 'TRSURG')
),
filtered_admissions AS (
  SELECT 
    a.hadm_id,
    CASE 
      WHEN a.hospital_expire_flag = 1 THEN 'in_hospital_mortality'
      WHEN a.discharge_location = 'HOME' THEN 'discharged_home'
      WHEN a.discharge_location IN (
        'SKILLED NURSING FACILITY', 
        'SNF', 
        'INPATIENT REHAB FACILITY', 
        'NURSING HOME', 
        'ASSISTED LIVING FAC', 
        'INTERMEDIATE CARE', 
        'CORRECTIONAL MEDICAL FACILITY', 
        'FEDERALLY QUALIFIED HEALTH CTR'
      ) THEN 'discharged_to_facility'
    END AS outcome,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24*60*60) AS los
  FROM admissions_with_age a
  INNER JOIN surgical_admissions s 
    ON a.hadm_id = s.hadm_id
  WHERE 
    a.gender = 'M'
    AND a.age_at_admit BETWEEN 67 AND 77
    AND a.dischtime IS NOT NULL  -- Ensure valid LOS calculation
)
SELECT 
  outcome,
  AVG(los) AS mean_los,
  STDDEV(los) AS sd_los,
  (COUNTIF(los <= 7) * 100.0 / COUNT(*)) AS percent_los_le7
FROM filtered_admissions
WHERE outcome IS NOT NULL  -- Only keep defined outcomes
GROUP BY outcome
ORDER BY 
  CASE outcome
    WHEN 'discharged_home' THEN 1
    WHEN 'discharged_to_facility' THEN 2
    WHEN 'in_hospital_mortality' THEN 3
  END;