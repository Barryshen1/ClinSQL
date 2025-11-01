WITH 
-- First, filter admissions based on age, gender, and admission source
eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.admission_type,
    a.admission_location,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 85 AND 95
    AND a.admission_location = 'TRANSFER FROM HOSP/OTHER FACILITY'
),

-- Identify index admissions
index_admissions AS (
  SELECT 
    subject_id,
    MIN(admittime) AS first_admit_time
  FROM 
    eligible_admissions
  GROUP BY 
    subject_id
),

-- Get the principal diagnosis for each admission
principal_diagnoses AS (
  SELECT 
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    di.long_title
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE 
    d.seq_num = 1  -- Principal diagnosis
),

-- Combine the information to count eligible admissions
eligible_patients AS (
  SELECT 
    ea.hadm_id
  FROM 
    eligible_admissions ea
  INNER JOIN 
    index_admissions ia ON ea.subject_id = ia.subject_id AND ea.admittime = ia.first_admit_time
  INNER JOIN 
    principal_diagnoses pd ON ea.hadm_id = pd.hadm_id
  WHERE 
    LOWER(pd.long_title) LIKE '%osteomyelitis%'  -- Osteomyelitis diagnosis
)

SELECT 
  COUNT(*) AS num_eligible_admissions
FROM 
  eligible_patients;