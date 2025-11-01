WITH 
  -- Filter and prepare data
  patient_stays AS (
    SELECT 
      p.subject_id,
      p.anchor_age,
      p.gender,
      ic.stay_id,
      ic.hadm_id,
      ic.los,
      CASE 
        WHEN p.dod IS NULL OR p.dod > ic.outtime THEN 'Discharged Alive'
        ELSE 'In-Hospital Death'
      END AS survival_status
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON ic.subject_id = p.subject_id
    WHERE 
      p.gender = 'F' AND 
      p.anchor_age BETWEEN 35 AND 45
  )

-- Calculate mean±SD LOS and percent with LOS < 7 days
SELECT 
  survival_status,
  AVG(los) AS mean_los,
  STDDEV(los) AS sd_los,
  COUNT(CASE WHEN los < 7 THEN 1 END) / COUNT(*) * 100 AS percent_los_less_than_7_days
FROM 
  patient_stays
GROUP BY 
  survival_status;