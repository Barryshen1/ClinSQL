WITH 
  -- Filter patients
  target_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      p.anchor_age, 
      p.gender,
      a.admission_type,
      a.discharge_location
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 41 AND 51
      AND a.admission_type IN ('EMERGENCY', 'URGENT')
      AND a.discharge_location NOT LIKE '%DEAD%'
      AND (a.admission_location LIKE '%chest pain%' OR a.admission_location LIKE '%AMI%')
  ),

  -- Retrieve initial Troponin T values
  troponin_values AS (
    SELECT 
      t.subject_id, 
      t.hadm_id, 
      le.charttime, 
      le.valuenum,
      dli.label
    FROM 
      target_patients t
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON 
      t.hadm_id = le.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON 
      le.itemid = dli.itemid
    WHERE 
      dli.label LIKE '%Troponin%'
      AND le.charttime = (
        SELECT 
          MIN(charttime) 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.labevents` 
        WHERE 
          hadm_id = t.hadm_id 
          AND itemid = le.itemid
      )
  ),

  -- Categorize Troponin T values
  categorized_troponin AS (
    SELECT 
      subject_id, 
      hadm_id, 
      valuenum,
      CASE 
        WHEN valuenum < 0.01 THEN 'normal'
        WHEN valuenum BETWEEN 0.01 AND 0.1 THEN 'borderline'
        ELSE 'elevated'
      END AS category,
      label
    FROM 
      troponin_values
  )

-- Calculate statistics
SELECT 
  category,
  COUNT(*) as count,
  COUNT(*) / SUM(COUNT(*)) OVER () as percentage,
  AVG(valuenum) as mean,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] as median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] as q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] as q3,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] as iqr
FROM 
  categorized_troponin
GROUP BY 
  category;