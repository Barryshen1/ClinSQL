WITH 
-- Identify male patients aged 39-49
patients_of_interest AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' AND 
    p.anchor_age BETWEEN 39 AND 49
),

-- Identify patients with status epilepticus
status_epilepticus AS (
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code LIKE '345.3%'
),

-- Identify QT-prolonging and bleeding-risk interactions
medication_interactions AS (
  SELECT 
    p.hadm_id,
    COUNT(DISTINCT pr.drug) AS num_drugs,
    ANY_VALUE(IF(pr.drug LIKE '%QT-prolonging%', 1, 0)) AS qt_prolonging,
    ANY_VALUE(IF(pr.drug LIKE '%bleeding risk%', 1, 0)) AS bleeding_risk
  FROM 
    patients_of_interest p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
      ON p.hadm_id = pr.hadm_id
  GROUP BY 
    p.hadm_id
),

-- Calculate LOS and mortality
outcomes AS (
  SELECT 
    p.hadm_id,
    TIMESTAMP_DIFF(p.dischtime, p.admittime, DAY) AS los,
    IF(p.deathtime IS NOT NULL, 1, 0) AS mortality
  FROM 
    patients_of_interest p
)

-- Final comparison
SELECT 
  'QT-prolonging' AS interaction_type,
  AVG(mi.num_drugs) AS medication_complexity,
  PERCENT_RANK() OVER (ORDER BY mi.num_drugs) AS percentile_rank,
  AVG(out.los) AS los,
  AVG(out.mortality) AS mortality
FROM 
  medication_interactions mi
JOIN 
  outcomes out ON mi.hadm_id = out.hadm_id
WHERE 
  mi.qt_prolonging = 1

UNION ALL

SELECT 
  'bleeding-risk' AS interaction_type,
  AVG(mi.num_drugs) AS medication_complexity,
  PERCENT_RANK() OVER (ORDER BY mi.num_drugs) AS percentile_rank,
  AVG(out.los) AS los,
  AVG(out.mortality) AS mortality
FROM 
  medication_interactions mi
JOIN 
  outcomes out ON mi.hadm_id = out.hadm_id
WHERE 
  mi.bleeding_risk = 1

UNION ALL

SELECT 
  'general' AS interaction_type,
  AVG(mi.num_drugs) AS medication_complexity,
  PERCENT_RANK() OVER (ORDER BY mi.num_drugs) AS percentile_rank,
  AVG(out.los) AS los,
  AVG(out.mortality) AS mortality
FROM 
  medication_interactions mi
JOIN 
  outcomes out ON mi.hadm_id = out.hadm_id
WHERE 
  mi.qt_prolonging = 0 AND mi.bleeding_risk = 0;