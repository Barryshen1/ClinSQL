WITH 
  -- Filter and calculate LOS for relevant patients
  icu_stays_filtered AS (
    SELECT 
      i.stay_id,
      i.subject_id,
      i.hadm_id,
      i.intime,
      i.outtime,
      TIMESTAMPDIFF(DAY, i.intime, i.outtime) AS los_days,
      a.discharge_location
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a 
        ON i.hadm_id = a.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 38 AND 48
      AND i.intime IS NOT NULL
      AND i.outtime IS NOT NULL
  ),
  
  -- Categorize discharge disposition
  discharge_disposition AS (
    SELECT 
      stay_id,
      los_days,
      CASE 
        WHEN discharge_location LIKE '%HOME%' THEN 'Home'
        WHEN discharge_location LIKE '%FACILITY%' THEN 'Facility'
        ELSE 'In-hospital death'
      END AS discharge_category
    FROM 
      icu_stays_filtered
  )

-- Calculate statistics for each discharge category
SELECT 
  discharge_category,
  AVG(los_days) AS mean_los,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los_days) AS median_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los_days) AS p75_los,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY los_days) AS p90_los
FROM 
  discharge_disposition
GROUP BY 
  discharge_category;