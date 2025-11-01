WITH 
-- Target population: Female inpatients aged 59-69 with PE
target_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
      WHERE di.hadm_id = a.hadm_id 
      AND di.icd_code LIKE '415%'  -- Pulmonary Embolism ICD code
    ) AS has_PE
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 59 AND 69
),

-- 30-day mortality
mortality_30d AS (
  SELECT 
    hadm_id,
    subject_id,
    CASE 
      WHEN deathtime IS NOT NULL AND TIMESTAMP_DIFF(deathtime, admittime, DAY) <= 30 THEN 1
      ELSE 0 
    END AS died_within_30d
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
)

-- Combine and calculate mean comorbidity risk score and 30-day mortality
SELECT 
  tp.hadm_id,
  tp.subject_id,
  tp.anchor_age,
  tp.gender,
  tp.has_PE,
  m.died_within_30d
FROM 
  target_population tp
JOIN 
  mortality_30d m ON tp.hadm_id = m.hadm_id;