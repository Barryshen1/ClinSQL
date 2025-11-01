WITH 
  -- Define a CTE to calculate LOS and filter patients
  patient_info AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      p.gender,
      p.anchor_age,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      t.eventtype,
      icu.stay_id,
      DATE_DIFF(a.dischtime, a.admittime, 'DAY') AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_hosp.transfers` t 
      ON a.subject_id = t.subject_id AND a.hadm_id = t.hadm_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` icu 
      ON a.hadm_id = icu.hadm_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 75 AND 85 
      AND t.eventtype = 'transfer in'
  ),
  
  -- Define a CTE to categorize discharge disposition
  discharge_disposition AS (
    SELECT 
      subject_id,
      hadm_id,
      los,
      hospital_expire_flag,
      CASE 
        WHEN dischtime IS NOT NULL AND hospital_expire_flag = 0 THEN 'home/hospice'
        WHEN hospital_expire_flag = 1 THEN 'in-hospital death'
        ELSE 'other'
      END AS disposition
    FROM 
      patient_info
  )

-- Calculate proportion with LOS ≥7 days and 7-day percentile
SELECT 
  disposition,
  COUNT(CASE WHEN los >= 7 THEN hadm_id END) / COUNT(hadm_id) AS proportion_los_geq_7,
  APPROX_QUANTILES(los, 0.7) OVER () AS los_70th_percentile
FROM 
  discharge_disposition
GROUP BY 
  disposition;