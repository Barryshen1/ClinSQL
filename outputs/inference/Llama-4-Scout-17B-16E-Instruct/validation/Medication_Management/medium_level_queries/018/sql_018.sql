WITH 
-- Define oral antidiabetic classes
oral_antidiabetics AS (
  SELECT 
    hadm_id,
    drug,
    CASE 
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%sulfonylurea%' THEN 'Sulfonylurea'
      WHEN LOWER(drug) LIKE '%dpp4%' THEN 'DPP4'
      WHEN LOWER(drug) LIKE '%sglt2%' THEN 'SGLT2'
      WHEN LOWER(drug) LIKE '%tzd%' OR LOWER(drug) LIKE '%thiazolidinedione%' THEN 'TZD'
      ELSE 'Other'
    END AS drug_class,
    starttime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

-- Filter patients with T2DM and heart failure
patients_with_conditions AS (
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.anchor_age BETWEEN 81 AND 91
    AND p.gender = 'F'
    AND dd.long_title LIKE '%Type 2 diabetes mellitus%'
    AND dd.long_title LIKE '%Heart failure%'
),

-- Identify prescriptions in first 72h and final 48h
prescriptions_time_frames AS (
  SELECT 
    p.hadm_id,
    oa.drug_class,
    CASE 
      WHEN TIMESTAMP_DIFF(oa.starttime, p.admittime, HOUR) BETWEEN 0 AND 72 THEN 'first_72h'
      WHEN TIMESTAMP_DIFF(p.dischtime, oa.starttime, HOUR) BETWEEN 0 AND 48 THEN 'final_48h'
      ELSE 'other'
    END AS time_frame
  FROM 
    patients_with_conditions p
  JOIN 
    oral_antidiabetics oa 
      ON p.hadm_id = oa.hadm_id
)

-- Calculate prevalence and absolute probability difference
SELECT 
  drug_class,
  time_frame,
  COUNT(DISTINCT hadm_id) AS num_patients,
  SUM(CASE WHEN time_frame = 'first_72h' THEN 1 ELSE 0 END) AS first_72h_count,
  SUM(CASE WHEN time_frame = 'final_48h' THEN 1 ELSE 0 END) AS final_48h_count
FROM 
  prescriptions_time_frames
GROUP BY 
  drug_class, time_frame
ORDER BY 
  drug_class;