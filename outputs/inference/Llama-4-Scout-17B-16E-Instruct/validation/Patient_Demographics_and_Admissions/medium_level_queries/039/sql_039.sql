WITH 
  -- Filter and calculate LOS for relevant patients
  patient_stays AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      p.anchor_age,
      p.gender,
      a.admission_type,
      a.discharge_location,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 37 AND 47
      AND a.admission_type IN ('Urgent', 'Emergency')
  ),

  -- Categorize discharge outcomes
  discharge_outcomes AS (
    SELECT 
      hadm_id,
      admittime,
      dischtime,
      anchor_age,
      gender,
      admission_type,
      los,
      CASE 
        WHEN discharge_location LIKE '%Home%' THEN 'Home'
        WHEN discharge_location LIKE '%Facility%' THEN 'Facility'
        ELSE 'In-hospital death'
      END AS discharge_outcome
    FROM 
      patient_stays
  )

-- Compute statistics for each discharge outcome
SELECT 
  discharge_outcome,
  AVG(los) AS mean_los,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) OVER (PARTITION BY discharge_outcome) AS p25_los,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) OVER (PARTITION BY discharge_outcome) AS p50_los,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) OVER (PARTITION BY discharge_outcome) AS p75_los,
  COUNTIF(los <= 7, los) / COUNT(*) AS percentile_rank_7day
FROM 
  discharge_outcomes
GROUP BY 
  discharge_outcome;