WITH 
patients AS (
  SELECT 
    subject_id, 
    gender, 
    anchor_age, 
    dod
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients`
),
admissions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    TIMESTAMP(admittime) AS admittime,
    TIMESTAMP(dischtime) AS dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),
prescriptions AS (
  SELECT 
    subject_id, 
    hadm_id, 
    TIMESTAMP(starttime) AS starttime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
),
-- Identify relevant patients
target_patients AS (
  SELECT 
    p.subject_id
  FROM 
    patients p
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND p.subject_id IN (
      SELECT 
        subject_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code LIKE 'E11%'  -- Type 2 diabetes
        OR icd_code LIKE 'I50%'  -- Heart failure
    )
),
-- Prescriptions with timing
prescription_timing AS (
  SELECT 
    tp.subject_id,
    p.hadm_id,
    pr.starttime,
    CASE
      WHEN TIMESTAMP_DIFF(pr.starttime, a.admittime, HOUR) <= 12 THEN 'first_12h'
      WHEN TIMESTAMP_DIFF(a.dischtime, pr.starttime, HOUR) <= 12 THEN 'last_12h'
      ELSE 'other'
    END AS prescription_timing
  FROM 
    target_patients tp
  JOIN 
    admissions a ON tp.subject_id = a.subject_id
  JOIN 
    prescriptions pr ON tp.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
)
SELECT 
  COUNT(CASE WHEN prescription_timing = 'first_12h' THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id) AS first_12h_percentage,
  COUNT(CASE WHEN prescription_timing = 'last_12h' THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id) AS last_12h_percentage,
  (COUNT(CASE WHEN prescription_timing = 'last_12h' THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id)) - 
  (COUNT(CASE WHEN prescription_timing = 'first_12h' THEN hadm_id END) * 100.0 / COUNT(DISTINCT hadm_id)) AS net_change
FROM 
  prescription_timing;