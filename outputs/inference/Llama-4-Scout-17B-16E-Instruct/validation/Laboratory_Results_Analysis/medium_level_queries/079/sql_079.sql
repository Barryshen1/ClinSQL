WITH 
  -- Identify troponin T lab events
  troponin_t AS (
    SELECT 
      le.subject_id,
      le.hadm_id,
      le.valuenum
    FROM 
      `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
      ON le.itemid = dli.itemid
    WHERE 
      dli.label LIKE '%Troponin T%'
      AND le.valuenum IS NOT NULL
      AND le.valuenum > 0.01
  ),

  -- Identify target patients
  target_patients AS (
    SELECT 
      a.subject_id,
      a.hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 82 AND 92
      AND a.admission_type IN ('elective', 'urgent', 'emergency')
      AND (a.admission_location LIKE '%chest pain%' OR a.admission_location LIKE '%AMI%')
  ),

  -- Join troponin and target patients
  patient_troponin AS (
    SELECT 
      tt.valuenum
    FROM 
      troponin_t tt
    JOIN 
      target_patients tp 
      ON tt.subject_id = tp.subject_id AND tt.hadm_id = tp.hadm_id
  )

-- Calculate statistics
SELECT 
  APPROX_QUANTILES(valuenum, 4)[0] AS p25,
  APPROX_QUANTILES(valuenum, 4)[1] AS p50,
  APPROX_QUANTILES(valuenum, 4)[2] AS p75,
  MIN(valuenum) AS min_val,
  MAX(valuenum) AS max_val
FROM 
  patient_troponin;