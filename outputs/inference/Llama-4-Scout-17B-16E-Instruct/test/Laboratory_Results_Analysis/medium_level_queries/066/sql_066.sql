WITH 
  -- Define hs-TnT categories
  hs_tnt_categories AS (
    SELECT 
      hadm_id,
      valuenum AS hs_tnt_value,
      CASE 
        WHEN valuenum < 6 THEN 'normal'
        WHEN valuenum BETWEEN 6 AND 14 THEN 'borderline'
        ELSE 'myocardial injury'
      END AS hs_tnt_category
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE 
      itemid = 43121  -- hs-TnT
      AND charttime = (SELECT MIN(charttime) FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le 
                      WHERE le.hadm_id = labevents.hadm_id AND le.itemid = 43121)
  ),
  
  -- Identify target patients
  target_patients AS (
    SELECT 
      a.hadm_id,
      p.gender,
      p.anchor_age
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 39 AND 49
      AND a.admission_type = 'Emergency'
      AND a.discharge_location LIKE '%Chest Pain%'
  ),

  -- Join patients with hs-TnT categories
  patient_hs_tnt AS (
    SELECT 
      hs_tnt_categories.hadm_id,
      hs_tnt_categories.hs_tnt_category,
      hs_tnt_categories.hs_tnt_value
    FROM 
      hs_tnt_categories
    JOIN 
      target_patients tp
    ON 
      hs_tnt_categories.hadm_id = tp.hadm_id
  )

-- Calculate statistics
SELECT 
  hs_tnt_category,
  COUNT(*) AS patient_count,
  COUNT(*) / SUM(COUNT(*)) OVER () AS percentage,
  AVG(hs_tnt_value) AS mean_hs_tnt,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY hs_tnt_value) AS median_hs_tnt,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY hs_tnt_value) AS q1_hs_tnt,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY hs_tnt_value) AS q3_hs_tnt
FROM 
  patient_hs_tnt
GROUP BY 
  hs_tnt_category
ORDER BY 
  hs_tnt_category;