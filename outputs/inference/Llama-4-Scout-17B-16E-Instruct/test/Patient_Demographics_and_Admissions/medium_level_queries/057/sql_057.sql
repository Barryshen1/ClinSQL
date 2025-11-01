WITH 
  -- Filter female patients aged 40-50
  filtered_patients AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      p.gender,
      p.anchor_age,
      ic.stay_id,
      ic.los,
      a.dischtime,
      a.deathtime,
      a.hospital_expire_flag
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON a.hadm_id = ic.hadm_id
    WHERE 
      p.gender = 'F' AND 
      p.anchor_age BETWEEN 40 AND 50
  ),

  -- Determine discharge outcome
  discharge_outcome AS (
    SELECT 
      hadm_id,
      subject_id,
      stay_id,
      los,
      CASE
        WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 'In-hospital death'
        WHEN dischtime IS NOT NULL AND discharge_location = 'Home' THEN 'Home'
        WHEN dischtime IS NOT NULL AND discharge_location = 'Hospice' THEN 'Hospice'
        ELSE 'Other'
      END AS discharge_outcome
    FROM 
      filtered_patients
  )

SELECT 
  discharge_outcome,
  APPROX_QUANTILES(los, 50)[OFFSET(0)] AS p50,
  APPROX_QUANTILES(los, 75)[OFFSET(0)] AS p75,
  APPROX_QUANTILES(los, 90)[OFFSET(0)] AS p90,
  APPROX_QUANTILES(los, 95)[OFFSET(0)] AS p95,
  COUNT(CASE WHEN los <= 7 THEN 1 END) / COUNT(*) AS pct_leq_7_days
FROM 
  discharge_outcome
WHERE 
  discharge_outcome IS NOT NULL
GROUP BY 
  discharge_outcome;