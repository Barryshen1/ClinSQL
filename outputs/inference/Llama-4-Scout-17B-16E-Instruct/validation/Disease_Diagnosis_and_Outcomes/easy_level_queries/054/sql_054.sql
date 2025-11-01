WITH 
  -- Filter admissions for males aged 51-61
  target_patients AS (
    SELECT 
      a.hadm_id,
      a.admittime,
      a.dischtime,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M'
      AND p.anchor_age BETWEEN 51 AND 61
  ),

  -- Filter for primary hemorrhagic stroke
  hemorrhagic_stroke_admissions AS (
    SELECT 
      hadm_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      (icd_version = '9' AND icd_code >= '430' AND icd_code <= '432')
      OR (icd_version = '10' AND icd_code >= 'I60' AND icd_code <= 'I62')
    AND seq_num = 1  -- Primary diagnosis
  )

SELECT 
  STDDEV(los_days) AS sd_los_days
FROM 
  target_patients tp
JOIN 
  hemorrhagic_stroke_admissions hs
ON 
  tp.hadm_id = hs.hadm_id;