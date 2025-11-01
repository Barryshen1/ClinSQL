WITH 
  -- Identify hemorrhagic stroke admissions
  hemorrhagic_stroke_admissions AS (
    SELECT 
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.admission_type,
      a.admission_location,
      a.insurance,
      p.anchor_age,
      p.gender
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    ON 
      a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON 
      a.hadm_id = d.hadm_id
    WHERE 
      p.gender = 'F'
      AND p.anchor_age BETWEEN 36 AND 46
      AND a.insurance = 'Medicare'
      AND a.admission_location LIKE '%Transfer from another hospital%'
      AND d.icd_code LIKE '430%'  -- ICD code for hemorrhagic stroke
      AND d.seq_num = 1  -- Principal diagnosis
  )

SELECT 
  COUNT(DISTINCT hadm_id) AS total_index_admissions
FROM 
  hemorrhagic_stroke_admissions;