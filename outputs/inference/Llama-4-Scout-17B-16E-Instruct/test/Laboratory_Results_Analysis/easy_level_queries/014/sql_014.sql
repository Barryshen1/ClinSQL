WITH 
  -- Define hemoglobin itemid
  hemoglobin_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
    WHERE label LIKE '%Hemoglobin%'
  ),
  
  -- Get discharge information and patient demographics
  patient_info AS (
    SELECT 
      a.hadm_id,
      a.dischtime,
      p.gender,
      p.anchor_age,
      a.admission_type
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
    WHERE 
      p.anchor_age = 45 AND 
      p.gender = 'F' 
  ),
  
  -- Filter for GI bleeding admissions
  gi_bleeding_admissions AS (
    SELECT DISTINCT 
      hadm_id 
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND a.subject_id = d.subject_id
    WHERE 
      d.icd_code LIKE '%K92.0%'  -- GI bleeding ICD code
  ),
  
  -- Get discharge day hemoglobin levels
  discharge_hemoglobin AS (
    SELECT 
      a.hadm_id,
      a.dischtime,
      l.valuenum
    FROM 
      patient_info a
    JOIN 
      gi_bleeding_admissions g 
    ON a.hadm_id = g.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
    CROSS JOIN 
      hemoglobin_itemid h
    WHERE 
      l.itemid = h.itemid AND 
      l.charttime <= a.dischtime AND 
      l.charttime >= TIMESTAMP_SUB(a.dischtime, INTERVAL 1 DAY)
  )

-- Calculate 75th percentile of discharge-day hemoglobin
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS percentile_75
FROM 
  discharge_hemoglobin;