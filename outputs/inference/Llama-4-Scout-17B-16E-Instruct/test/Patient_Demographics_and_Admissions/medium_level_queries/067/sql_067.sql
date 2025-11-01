WITH 
-- Filter and calculate LOS for relevant patients
patients_filtered AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    s.curr_service,
    CASE 
      WHEN a.discharge_location = 'Home' THEN 'Home'
      WHEN a.discharge_location LIKE '%Hospice%' THEN 'Hospice'
      ELSE 'In-hospital death'
    END AS discharge_disposition
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.services` s 
      ON a.hadm_id = s.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 49 AND 59
    AND s.curr_service = 'Medicine'
),

-- Calculate LOS
los_calculated AS (
  SELECT 
    subject_id,
    hadm_id,
    anchor_age,
    gender,
    admittime,
    dischtime,
    curr_service,
    discharge_disposition,
    DATE_DIFF(dischtime, admittime, DAY) AS los_days
  FROM 
    patients_filtered
)

-- Calculate proportions and percentile
SELECT 
  discharge_disposition,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS patients_los_7_or_more,
  SUM(CASE WHEN los_days >= 14 THEN 1 ELSE 0 END) AS patients_los_14_or_more,
  PERCENTILE_CONT(0.7) WITHIN GROUP (ORDER BY los_days) AS los_70th_percentile
FROM 
  los_calculated
GROUP BY 
  discharge_disposition;