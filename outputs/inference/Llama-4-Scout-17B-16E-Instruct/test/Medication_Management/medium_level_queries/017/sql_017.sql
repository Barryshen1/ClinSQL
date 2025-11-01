WITH 
-- Identify population of interest
population AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu`.icustays i ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND i.los >= 144
    AND a.subject_id IN (
      SELECT 
        subject_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
      WHERE 
        icd_code IN ('250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9')  -- Diabetes
        OR icd_code IN ('428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9')  -- Heart Failure
    )
),

-- Identify medications of interest
medications AS (
  SELECT 
    subject_id,
    hadm_id,
    pharmacy_id,
    drug,
    starttime,
    stoptime
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE 
    drug_type = 'medication'
    AND drug IN (
      'Antidiabetics',  -- Placeholder, actual drug names needed
      'Beta-blockers',  -- Placeholder, actual drug names needed
      'ACEi/ARB/ARNI',  -- Placeholder, actual drug names needed
      'Loop diuretics'  -- Placeholder, actual drug names needed
    )
),

-- Medication usage in first and last 72 hours
medication_usage AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    m.drug,
    CASE 
      WHEN TIMESTAMP_DIFF(m.starttime, p.intime, HOUR) BETWEEN 0 AND 72 THEN 'first_72h'
      WHEN TIMESTAMP_DIFF(m.stoptime, p.intime, HOUR) BETWEEN 0 AND 72 AND TIMESTAMP_DIFF(m.stoptime, p.outtime, HOUR) >= 0 THEN 'last_72h'
      ELSE 'outside_72h'
    END AS period
  FROM 
    population p
  JOIN 
    medications m ON p.hadm_id = m.hadm_id
)

-- Calculate medication usage percentages and counts
SELECT 
  drug,
  period,
  COUNT(DISTINCT subject_id) AS patient_count
FROM 
  medication_usage
GROUP BY 
  drug, period
ORDER BY 
  drug, period;