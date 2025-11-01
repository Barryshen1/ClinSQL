WITH 
  -- Filter patients by age and gender
  filtered_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime, 
      a.dischtime
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 43 AND 53
  ),

  -- Filter patients with primary hemorrhagic stroke
  hemorrhagic_stroke_patients AS (
    SELECT 
      fp.subject_id, 
      fp.hadm_id, 
      fp.admittime, 
      fp.dischtime
    FROM 
      filtered_patients fp
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON fp.hadm_id = d.hadm_id
    WHERE 
      d.icd_code LIKE '430%'  -- ICD code for hemorrhagic stroke
      AND d.seq_num = 1  -- Primary diagnosis
  )

-- Calculate hospital LOS and SD
SELECT 
  STDDEV(DATE_DIFF(dischtime, admittime, DAY)) AS sd_los
FROM 
  hemorrhagic_stroke_patients;