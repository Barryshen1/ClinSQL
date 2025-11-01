WITH 
-- Identify DKA patients
dka_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 59 AND 69
    AND d.icd_code LIKE '%250.1%'  -- DKA ICD-9 code
    OR d.icd_code LIKE '%E10.1%'  -- DKA ICD-10 code
),

-- Identify AKI and ARDS
aki_ards AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN icd_code LIKE '%584%' THEN 'AKI'
      WHEN icd_code LIKE '%518.8%' THEN 'ARDS'
    END AS condition
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
),

-- 30-day mortality
mortality AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN deathtime IS NOT NULL AND deathtime <= TIMESTAMP_ADD(admittime, INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS thirty_day_mortality
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
)

-- Final query
SELECT 
  COUNT(DISTINCT dp.hadm_id) AS num_patients,
  AVG(CASE WHEN m.thirty_day_mortality = 1 THEN 1 ELSE 0 END) AS thirty_day_mortality_rate
FROM 
  dka_patients dp
  LEFT JOIN mortality m ON dp.hadm_id = m.hadm_id
  LEFT JOIN aki_ards a ON dp.hadm_id = a.hadm_id;