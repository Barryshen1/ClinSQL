WITH 
  -- Define age range and gender
  eligible_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.deathtime,
      a.admission_type,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 67 AND 77
      AND a.admission_type = 'Surgical'
  ),

  -- Determine discharge disposition and calculate LOS
  patient_outcomes AS (
    SELECT 
      ep.subject_id,
      ep.hadm_id,
      ep.admittime,
      ep.dischtime,
      ep.deathtime,
      CASE
        WHEN ep.dischtime IS NOT NULL AND ep.deathtime IS NULL THEN 
          CASE
            WHEN a.discharge_location LIKE '%HOME%' THEN 'Discharged Home'
            WHEN a.discharge_location LIKE '%FACILITY%' THEN 'Discharged to Facility'
            ELSE 'Other'
          END
        WHEN ep.deathtime IS NOT NULL THEN 'In-hospital Mortality'
        ELSE 'Unknown'
      END AS disposition
    FROM 
      eligible_patients ep
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON 
      ep.hadm_id = a.hadm_id
  )

SELECT 
  po.disposition,
  AVG(TIMESTAMP_DIFF(po.dischtime, po.admittime, DAY)) AS mean_los,
  STDDEV(TIMESTAMP_DIFF(po.dischtime, po.admittime, DAY)) AS sd_los,
  COUNT(CASE WHEN TIMESTAMP_DIFF(po.dischtime, po.admittime, DAY) <= 7 THEN 1 END) / COUNT(*) * 100 AS percent_los_leq_7_days
FROM 
  patient_outcomes po
WHERE 
  po.disposition IN ('Discharged Home', 'Discharged to Facility', 'In-hospital Mortality')
GROUP BY 
  po.disposition;