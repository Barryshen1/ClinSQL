WITH 
-- Identify population of interest
population AS (
  SELECT 
    a.hadm_id AS p_hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender,
    d.icd_code,
    dd.long_title AS diagnosis
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
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND (d.icd_code LIKE '%250%' OR d.icd_code LIKE '%K92.2%')  -- Diabetes
    AND (d.icd_code LIKE '%428%' OR d.icd_code LIKE '%I50%')  -- Heart Failure
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 36
),

-- Identify GLP-1 injections
glp1_injections AS (
  SELECT 
    p.hadm_id AS g_hadm_id,
    TIMESTAMP_DIFF(pr.starttime, p.admittime, HOUR) AS hours_since_admission,
    pr.drug
  FROM 
    population p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
      ON p.p_hadm_id = pr.hadm_id
  WHERE 
    LOWER(pr.drug) LIKE '%glp-1%' 
    OR LOWER(pr.drug) LIKE '%exenatide%' 
    OR LOWER(pr.drug) LIKE '%liraglutide%' 
    OR LOWER(pr.drug) LIKE '%dulaglutide%' 
    OR LOWER(pr.drug) LIKE '%semaglutide%'
)

-- Calculate percentages
SELECT 
  COUNT(DISTINCT CASE WHEN hours_since_admission <= 24 THEN g_hadm_id END) * 100.0 / COUNT(DISTINCT p.p_hadm_id) AS percent_glp1_first_24h,
  COUNT(DISTINCT CASE WHEN hours_since_admission >= TIMESTAMP_DIFF(p.admittime, p.dischtime, HOUR) - 12 THEN g_hadm_id END) * 100.0 / COUNT(DISTINCT p.p_hadm_id) AS percent_glp1_final_12h
FROM 
  population p
  LEFT JOIN glp1_injections g ON p.p_hadm_id = g.g_hadm_id;