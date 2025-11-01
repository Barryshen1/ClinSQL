WITH
-- Get female patients aged 40-50
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 40 AND 50
),

-- Get admissions for these patients
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN female_patients p ON a.subject_id = p.subject_id
),

-- Identify admissions with neutropenic fever
neutropenic_fever_admissions AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.los_hours,
    pa.hospital_expire_flag
  FROM patient_admissions pa
  WHERE EXISTS (
    -- Fever condition (temperature > 38°C)
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
    WHERE ce.hadm_id = pa.hadm_id
      AND di.label LIKE '%Temperature%'
      AND ce.valuenum > 38
      AND ce.charttime BETWEEN pa.admittime AND pa.dischtime
  )
  AND EXISTS (
    -- Neutropenia condition (ANC < 500)
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
    WHERE le.hadm_id = pa.hadm_id
      AND (dli.label LIKE '%Neutrophil%' OR dli.label LIKE '%ANC%')
      AND le.valuenum < 500
      AND le.charttime BETWEEN pa.admittime AND pa.dischtime
  )
),

-- Calculate medication complexity score (count of unique medications in first 48 hours)
medication_complexity AS (
  SELECT
    nfa.hadm_id,
    COUNT(DISTINCT p.drug) AS complexity_score
  FROM neutropenic_fever_admissions nfa
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON nfa.hadm_id = p.hadm_id
    AND p.starttime BETWEEN nfa.admittime AND TIMESTAMP_ADD(nfa.admittime, INTERVAL 48 HOUR)
  GROUP BY nfa.hadm_id
),

-- Add quartile information
admissions_with_quartiles AS (
  SELECT
    nfa.*,
    mc.complexity_score,
    NTILE(4) OVER (ORDER BY mc.complexity_score) AS quartile
  FROM neutropenic_fever_admissions nfa
  JOIN medication_complexity mc ON nfa.hadm_id = mc.hadm_id
),

-- Calculate 30-day readmission flag
readmissions AS (
  SELECT
    a1.hadm_id AS original_hadm_id,
    a1.subject_id AS subject_id,
    MAX(CASE WHEN a2.admittime BETWEEN a1.dischtime AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY) THEN 1 ELSE 0 END) AS has_30day_readmission
  FROM patient_admissions a1
  LEFT JOIN patient_admissions a2
    ON a1.subject_id = a2.subject_id
    AND a1.hadm_id != a2.hadm_id
    AND a2.admittime BETWEEN a1.dischtime AND TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
  GROUP BY a1.hadm_id, a1.subject_id
)

-- Final aggregation by quartile
SELECT
  quartile,
  COUNT(DISTINCT subject_id) AS patient_count,
  AVG(complexity_score) AS mean_complexity_score,
  MIN(complexity_score) AS min_complexity_score,
  MAX(complexity_score) AS max_complexity_score,
  AVG(los_hours/24) AS mean_los_days,
  ROUND(100 * AVG(hospital_expire_flag), 1) AS mortality_percentage,
  ROUND(100 * AVG(has_30day_readmission), 1) AS readmission_30day_percentage
FROM admissions_with_quartiles aq
LEFT JOIN readmissions r ON aq.hadm_id = r.original_hadm_id
GROUP BY quartile
ORDER BY quartile;