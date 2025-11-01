WITH 
  -- Identify hs-TnT itemid
  hs_tnt_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
    WHERE label LIKE '%hs-TnT%' OR label = 'Troponin T, high sensitivity'
  ),

  -- Get initial hs-TnT values for male patients aged 61-71 admitted for chest pain
  patient_data AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      p.anchor_age,
      le.valuenum AS hs_tnt_value
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON a.hadm_id = le.hadm_id
    JOIN 
      hs_tnt_itemid hti 
      ON le.itemid = hti.itemid
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 61 AND 71
      AND a.admission_type = 'Emergency'
      AND le.charttime = ( 
        SELECT MIN(charttime) 
        FROM `physionet-data.mimiciv_3_1_hosp.labevents` le2 
        WHERE le2.hadm_id = a.hadm_id AND le2.itemid = hti.itemid
      )
  )

-- Classify and calculate percent distribution
SELECT 
  CASE 
    WHEN hs_tnt_value < 14 THEN 'Normal'
    WHEN hs_tnt_value BETWEEN 14 AND 30 THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END AS hs_tnt_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) / SUM(COUNT(*)) OVER (), 2) * 100 AS percent_distribution
FROM 
  patient_data
GROUP BY 
  CASE 
    WHEN hs_tnt_value < 14 THEN 'Normal'
    WHEN hs_tnt_value BETWEEN 14 AND 30 THEN 'Borderline'
    ELSE 'Myocardial Injury'
  END
ORDER BY 
  hs_tnt_category;