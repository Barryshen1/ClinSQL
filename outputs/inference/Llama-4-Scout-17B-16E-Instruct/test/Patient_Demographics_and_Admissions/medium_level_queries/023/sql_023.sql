WITH 
  -- Calculate LOS and filter patients
  patient_stay AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.admission_location,
      p.gender,
      p.anchor_age,
      CASE 
        WHEN a.dischtime IS NULL THEN 
          TIMESTAMP_DIFF(CURRENT_TIMESTAMP, a.admittime, DAY)
        ELSE 
          DATE_DIFF(a.dischtime, a.admittime)
      END AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 41 AND 51
      AND a.admission_location = 'Emergency Department'
  ),
  
  -- Categorize discharge disposition
  discharge_category AS (
    SELECT 
      subject_id,
      hadm_id,
      los_days,
      CASE 
        WHEN deathtime IS NOT NULL THEN 'In-hospital death'
        WHEN discharge_location LIKE '%Home%' THEN 'Home'
        ELSE 'Facility'
      END AS discharge_disposition
    FROM 
      patient_stay
  )

-- Calculate proportion with LOS ≥ 7 days and percentile rank of 10-day LOS
SELECT 
  discharge_disposition,
  COUNT(CASE WHEN los_days >= 7 THEN 1 END) / COUNT(*) AS proportion_los_geq_7,
  APPROX_QUANTILES(los_days, 1000)[OFFSET(100)] AS percentile_10_los
FROM 
  discharge_category
GROUP BY 
  discharge_disposition;