WITH 
  -- Identify ischemic heart disease admissions
  ihd_admissions AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime,
      p.gender,
      p.anchor_age
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 47 AND 57
      AND d.icd_code LIKE 'I24%'  -- Ischemic heart disease ICD code
  ),
  
  -- Get first Troponin-T values
  troponin_values AS (
    SELECT 
      ihad.subject_id, 
      ihad.hadm_id, 
      l.valueuom, 
      l.valuenum AS troponin_value
    FROM 
      ihd_admissions ihad
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.labevents` l ON ihad.hadm_id = l.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
    WHERE 
      dl.label LIKE '%Troponin%' 
      AND l.charttime = (SELECT MIN(charttime) FROM `physionet-data.mimiciv_3_1_hosp.labevents` le WHERE le.hadm_id = ihad.hadm_id AND le.itemid = l.itemid)
      AND l.valuenum > 0.014  -- Exceeds 99th percentile (>0.014 ng/mL)
  )

SELECT 
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY troponin_value) AS median,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY troponin_value) AS q1,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY troponin_value) AS q3
FROM 
  troponin_values;