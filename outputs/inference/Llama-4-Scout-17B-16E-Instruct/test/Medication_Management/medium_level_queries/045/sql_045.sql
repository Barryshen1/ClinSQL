WITH 
-- Identify target population
target_population AS (
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
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 54 AND 64
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN (
          SELECT 
            icd_code 
          FROM 
            `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` 
          WHERE 
            long_title IN ('Diabetes mellitus', 'Heart failure')
        )
    )
),

-- Medication orders for target population
medications AS (
  SELECT 
    tp.subject_id, 
    tp.hadm_id, 
    p.starttime, 
    p.drug,
    CASE 
      WHEN p.drug LIKE '%insulin%' THEN 'insulin'
      WHEN p.form_rx LIKE '%oral%' THEN 'oral'
      ELSE 'other'
    END AS medication_type
  FROM 
    target_population tp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
      ON tp.hadm_id = p.hadm_id
),

-- First 12 hours and last 48 hours
time_periods AS (
  SELECT 
    m.hadm_id,
    m.starttime,
    a.admittime,
    a.dischtime,
    CASE 
      WHEN TIMESTAMP_DIFF(m.starttime, a.admittime, HOUR) <= 12 THEN 'first_12_hours'
      WHEN TIMESTAMP_DIFF(a.dischtime, m.starttime, HOUR) <= 48 THEN 'last_48_hours'
      ELSE 'other'
    END AS time_period
  FROM 
    medications m
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON m.hadm_id = a.hadm_id
),

-- Prevalence of insulin vs. oral agents
prevalence AS (
  SELECT 
    tp.time_period,
    m.medication_type,
    COUNT(DISTINCT m.hadm_id) AS patient_count
  FROM 
    time_periods tp
  JOIN 
    medications m 
      ON tp.hadm_id = m.hadm_id AND tp.starttime = m.starttime
  WHERE 
    m.medication_type IN ('insulin', 'oral')
  GROUP BY 
    tp.time_period, 
    m.medication_type
)

-- Calculate net change
SELECT 
  time_period,
  medication_type,
  patient_count,
  SUM(patient_count) OVER (PARTITION BY medication_type) AS total_patients,
  LAG(patient_count) OVER (PARTITION BY medication_type ORDER BY time_period) AS prev_period_count,
  patient_count - LAG(patient_count) OVER (PARTITION BY medication_type ORDER BY time_period) AS net_change
FROM 
  prevalence
ORDER BY 
  time_period, 
  medication_type;