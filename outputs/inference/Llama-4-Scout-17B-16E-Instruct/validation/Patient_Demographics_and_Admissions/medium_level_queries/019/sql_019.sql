WITH 
  -- Filter and calculate LOS for relevant patients
  patient_stays AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.discharge_location,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 63 AND 73
      AND a.hadm_id IN (
        SELECT 
          hadm_id 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.transfers` 
        WHERE 
          eventtype = 'transferin'
      )
  ),
  
  -- Categorize discharge locations
  discharge_categories AS (
    SELECT 
      hadm_id,
      los_days,
      discharge_location,
      CASE 
        WHEN discharge_location LIKE '%Home%' THEN 'Home'
        WHEN discharge_location LIKE '%Hospice%' THEN 'Hospice'
        ELSE 'In-hospital death'
      END AS discharge_category
    FROM 
      patient_stays
  )

-- Calculate mean and SD of LOS by discharge category
SELECT 
  discharge_category,
  AVG(los_days) AS mean_los,
  STDDEV(los_days) AS sd_los
FROM 
  discharge_categories
GROUP BY 
  discharge_category;