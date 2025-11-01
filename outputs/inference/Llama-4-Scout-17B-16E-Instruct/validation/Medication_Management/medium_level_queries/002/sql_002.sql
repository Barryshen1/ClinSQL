WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),

-- Identify medication administration
medication_admin AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.admittime,
    p.dischtime,
    ph.starttime,
    ph.stoptime
  FROM 
    patients_of_interest p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  ON 
    p.hadm_id = ph.hadm_id
  WHERE 
    ph.medication IN ('Exenatide', 'Liraglutide', 'Albiglutide', 'Dulaglutide')
)

-- Calculate prevalence and difference
SELECT 
  COUNT(DISTINCT CASE WHEN ma.starttime BETWEEN ma.admittime AND TIMESTAMP_ADD(ma.admittime, INTERVAL 48 HOUR) THEN ma.hadm_id END) * 1.0 / 
  COUNT(DISTINCT ma.hadm_id) AS first_48h_prevalence,
  COUNT(DISTINCT CASE WHEN ma.starttime BETWEEN TIMESTAMP_SUB(ma.dischtime, INTERVAL 12 HOUR) AND ma.dischtime THEN ma.hadm_id END) * 1.0 / 
  COUNT(DISTINCT ma.hadm_id) AS final_12h_prevalence,
  COUNT(DISTINCT CASE WHEN ma.starttime BETWEEN ma.admittime AND TIMESTAMP_ADD(ma.admittime, INTERVAL 48 HOUR) THEN ma.hadm_id END) * 1.0 / 
  COUNT(DISTINCT ma.hadm_id) - 
  COUNT(DISTINCT CASE WHEN ma.starttime BETWEEN TIMESTAMP_SUB(ma.dischtime, INTERVAL 12 HOUR) AND ma.dischtime THEN ma.hadm_id END) * 1.0 / 
  COUNT(DISTINCT ma.hadm_id) AS pp_difference
FROM 
  medication_admin ma;