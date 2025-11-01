WITH 
  -- Define a CTE to get patient demographics and hadm_id
  patient_demographics AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      a.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 64 AND 74
  ),
  
  -- Define a CTE to get prescriptions for aspirin and P2Y12 inhibitors
  antiplatelet_prescriptions AS (
    SELECT 
      p.subject_id,
      p.hadm_id,
      pr.starttime,
      pr.stoptime,
      DATEDIFF(pr.stoptime, pr.starttime) AS duration_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN 
      patient_demographics p ON pr.subject_id = p.subject_id AND pr.hadm_id = p.hadm_id
    WHERE 
      pr.drug LIKE '%aspirin%' 
      AND EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr2 
        WHERE pr2.subject_id = pr.subject_id 
          AND pr2.hadm_id = pr.hadm_id 
          AND (pr2.drug LIKE '%clopidogrel%' 
               OR pr2.drug LIKE '%prasugrel%' 
               OR pr2.drug LIKE '%ticagrelor%')
      )
  ),

  -- Calculate median duration
  median_duration AS (
    SELECT 
      APPROX_QUANTILES(duration_days, 0.5)[OFFSET(1)] AS median_days
    FROM 
      antiplatelet_prescriptions
      WHERE stoptime IS NOT NULL  # Ensure stoptime is not null
  )

-- Select the median duration
SELECT 
  median_days
FROM 
  median_duration;