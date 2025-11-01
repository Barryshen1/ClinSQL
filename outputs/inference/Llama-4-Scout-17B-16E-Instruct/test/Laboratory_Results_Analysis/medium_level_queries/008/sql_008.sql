WITH 
-- Define Troponin T categories
troponin_categories AS (
  SELECT 
    l.hadm_id,
    l.subject_id,
    l.itemid,
    l.charttime,
    l.valuenum,
    CASE
      WHEN l.valuenum < 0.01 THEN 'Normal/Minimal'
      WHEN l.valuenum BETWEEN 0.01 AND 0.1 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` i ON l.itemid = i.itemid
  WHERE 
    i.label LIKE '%Troponin T%'
),

-- Identify earliest Troponin T measurement for each admission
earliest_troponin AS (
  SELECT 
    hadm_id,
    subject_id,
    itemid,
    charttime,
    troponin_category,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM 
    troponin_categories
),

-- Identify eligible patients
eligible_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admission_type,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 87 AND 97
    AND p.gender = 'M'
    AND a.admission_type LIKE '%ACS%'
),

-- Link patients with their index Troponin T category
patient_troponin AS (
  SELECT 
    ep.subject_id,
    ep.hadm_id,
    ep.hospital_expire_flag,
    et.troponin_category
  FROM 
    eligible_patients ep
  JOIN 
    earliest_troponin et ON ep.hadm_id = et.hadm_id AND et.rn = 1
)

-- Calculate counts, percentages, and mortality rates
SELECT 
  troponin_category,
  COUNT(DISTINCT hadm_id) AS patient_count,
  ROUND(COUNT(DISTINCT hadm_id) / SUM(COUNT(DISTINCT hadm_id)) OVER (), 4) AS percentage,
  SUM(hospital_expire_flag) AS mortality_count,
  ROUND(SUM(hospital_expire_flag * 1.0) / COUNT(DISTINCT hadm_id), 4) AS mortality_rate
FROM 
  patient_troponin
GROUP BY 
  troponin_category;