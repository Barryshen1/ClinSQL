WITH 
-- Identify patients of interest
patients_of_interest AS (
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
  WHERE 
    p.anchor_age BETWEEN 80 AND 90 
    AND p.gender = 'M'
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code LIKE '995.92' OR icd_code LIKE 'S% sepsis%'
    )
),

-- Identify medications of interest
qt_prolonging_drugs AS (
  SELECT 
    drug 
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` 
  WHERE 
    drug IN ('QT-prolonging drugs list') -- Assume this list is provided
),

bleeding_risk_drugs AS (
  SELECT 
    drug 
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` 
  WHERE 
    drug IN ('bleeding-risk drugs list') -- Assume this list is provided
),

-- Identify patients on both types of drugs
patients_on_drugs AS (
  SELECT 
    poi.subject_id, 
    poi.hadm_id
  FROM 
    patients_of_interest poi
  JOIN 
    qt_prolonging_drugs qtd 
      ON poi.hadm_id IN (
        SELECT 
          hadm_id 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.prescriptions` 
        WHERE 
          drug = qtd.drug
      )
  JOIN 
    bleeding_risk_drugs brd 
      ON poi.hadm_id IN (
        SELECT 
          hadm_id 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.prescriptions` 
        WHERE 
          drug = brd.drug
      )
),

-- Calculate medication complexity score (example: count of unique medications)
medication_complexity AS (
  SELECT 
    subject_id, 
    hadm_id, 
    COUNT(DISTINCT drug) AS complexity_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` 
  GROUP BY 
    subject_id, 
    hadm_id
),

-- Calculate percentile ranks
percentile_ranks AS (
  SELECT 
    subject_id, 
    hadm_id, 
    complexity_score,
    PERCENT_RANK() OVER (ORDER BY complexity_score) AS percentile_rank
  FROM 
    medication_complexity
)

-- Final query to identify top quartile and compare outcomes
SELECT 
  pr.subject_id, 
  pr.hadm_id, 
  pr.complexity_score,
  pr.percentile_rank,
  ic.stay_id,
  ic.intime,
  ic.outtime,
  a.hospital_expire_flag
FROM 
  percentile_ranks pr
JOIN 
  patients_of_interest poi 
    ON pr.subject_id = poi.subject_id AND pr.hadm_id = poi.hadm_id
LEFT JOIN 
  `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON pr.hadm_id = ic.hadm_id
JOIN 
  `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON pr.hadm_id = a.hadm_id
WHERE 
  pr.percentile_rank >= 0.75 -- Top quartile
ORDER BY 
  pr.complexity_score DESC;