WITH 
-- Target population with intracranial hemorrhage
target_population AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    MIN(CASE WHEN di.icd_code LIKE '907%' THEN 1 ELSE 0 END) AS has_intracranial_hemorrhage
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'F' AND p.anchor_age BETWEEN 44 AND 54
  GROUP BY 
    a.subject_id, a.hadm_id, p.anchor_age, p.gender
  HAVING 
    MIN(CASE WHEN di.icd_code LIKE '907%' THEN 1 ELSE 0 END) = 1
),

-- 90-day mortality
mortality AS (
  SELECT 
    subject_id, 
    hadm_id, 
    CASE 
      WHEN deathtime IS NOT NULL AND deathtime <= TIMESTAMP_ADD(admittime, INTERVAL 90 DAY) THEN 1 
      ELSE 0 
    END AS died_within_90_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Median LOS for survivors
los AS (
  SELECT 
    subject_id, 
    hadm_id, 
    DATE_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE 
    a.dischtime IS NOT NULL
)

SELECT 
  tp.subject_id,
  tp.hadm_id,
  tp.anchor_age,
  tp.gender,
  tp.has_intracranial_hemorrhage,
  m.died_within_90_days,
  l.los_days
FROM 
  target_population tp
  LEFT JOIN mortality m ON tp.subject_id = m.subject_id AND tp.hadm_id = m.hadm_id
  LEFT JOIN los l ON tp.subject_id = l.subject_id AND tp.hadm_id = l.hadm_id
ORDER BY 
  tp.anchor_age, tp.gender, tp.has_intracranial_hemorrhage, m.died_within_90_days, l.los_days;