WITH 
-- Filter and calculate LOS for relevant patients
patients_filtered AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    a.discharge_location,
    a.hospital_expire_flag,
    a.admission_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.admission_type = 'medicine'
),

-- Categorize discharge location
discharge_category AS (
  SELECT 
    hadm_id,
    los,
    admittime,
    dischtime,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%Home%' THEN 'Home'
      WHEN discharge_location LIKE '%Hospice%' THEN 'Hospice'
      ELSE 'Other' 
    END AS discharge_location_category
  FROM 
    patients_filtered
)

-- Calculate statistics
SELECT 
  discharge_location_category,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 0.5)[OFFSET(1)] AS median_los,
  SUM(CASE WHEN los <= 5 THEN 1 ELSE 0 END) / COUNT(*) AS proportion_los_leq_5
FROM 
  discharge_category
GROUP BY 
  discharge_location_category;