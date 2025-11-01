WITH 
  -- Calculate hospital length of stay and filter patients
  patient_stay AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      p.anchor_age,
      p.gender,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      a.discharge_location,
      DATE_DIFF(a.dischtime, a.admittime) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 75 AND 85
  ),
  
  -- Categorize discharge disposition
  categorized_stay AS (
    SELECT 
      hadm_id,
      subject_id,
      anchor_age,
      gender,
      admittime,
      dischtime,
      hospital_expire_flag,
      discharge_location,
      los_days,
      CASE 
        WHEN discharge_location LIKE '%Home%' THEN 'Discharged Home'
        WHEN discharge_location LIKE '%Hospice%' THEN 'Discharged to Hospice'
        WHEN hospital_expire_flag = 1 THEN 'In-Hospital Mortality'
        ELSE 'Other'
      END AS discharge_category
    FROM 
      patient_stay
  )

-- Calculate mean and SD of length of stay by category
SELECT 
  discharge_category,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los
FROM 
  categorized_stay
WHERE 
  discharge_category IN ('Discharged Home', 'Discharged to Hospice', 'In-Hospital Mortality')
GROUP BY 
  discharge_category;