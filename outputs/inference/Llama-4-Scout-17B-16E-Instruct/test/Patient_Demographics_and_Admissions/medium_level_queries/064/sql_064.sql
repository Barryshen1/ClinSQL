WITH 
  -- Patient demographics and admission information
  patient_info AS (
    SELECT 
      p.subject_id,
      p.gender,
      p.anchor_age,
      a.hadm_id,
      a.admission_type,
      a.discharge_location,
      a.hospital_expire_flag,
      a.dischtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      p.subject_id = a.subject_id
    WHERE 
      p.gender = 'F' AND p.anchor_age BETWEEN 63 AND 73
  ),
  
  -- ICU stay information
  icu_stays AS (
    SELECT 
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      DATE_DIFF(outtime, intime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  -- Combine patient and ICU stay information
  combined_info AS (
    SELECT 
      pi.subject_id,
      pi.hadm_id,
      pi.discharge_location,
      pi.hospital_expire_flag,
      icu.los
    FROM 
      patient_info pi
    JOIN 
      icu_stays icu
    ON 
      pi.hadm_id = icu.hadm_id
  ),
  
  -- Determine discharge outcome
  discharge_outcome AS (
    SELECT 
      subject_id,
      hadm_id,
      los,
      CASE 
        WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
        WHEN discharge_location LIKE '%Hospice%' THEN 'Hospice'
        ELSE 'Home'
      END AS discharge_outcome
    FROM 
      combined_info
  )

-- Calculate statistics by discharge outcome
SELECT 
  discharge_outcome,
  COUNT(*) AS n,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 0.5)[OFFSET(0)] AS median_los,
  SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(*) * 100 AS percent_los_leq_10_days
FROM 
  discharge_outcome
GROUP BY 
  discharge_outcome;