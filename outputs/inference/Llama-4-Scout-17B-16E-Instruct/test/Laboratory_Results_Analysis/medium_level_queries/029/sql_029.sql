WITH 
-- Identify Troponin T lab item
troponin_t_item AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%Troponin T%'
),

-- Patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    l.valueuom,
    l.valuenum,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l 
      ON a.hadm_id = l.hadm_id
  JOIN 
    troponin_t_item tti 
      ON l.itemid = tti.itemid
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 58 AND 68
    AND (a.discharge_location LIKE '%CHEST PAIN%' 
          OR a.discharge_location LIKE '%AMI%' 
          OR EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
            WHERE di.hadm_id = a.hadm_id 
              AND di.icd_code LIKE '%786.5%'  -- Chest pain ICD-9
          ) 
          OR EXISTS (
            SELECT 1 
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
            JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
              ON di.icd_code = dd.icd_code 
              AND di.icd_version = dd.icd_version
            WHERE di.hadm_id = a.hadm_id 
              AND dd.long_title LIKE '%Acute Myocardial Infarction%'
          ))
    AND l.charttime = (SELECT MIN(charttime) 
                       FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
                       WHERE le.hadm_id = a.hadm_id 
                         AND le.itemid = tti.itemid)
    AND l.valuenum > 0.04
),

-- Calculate statistics
stats AS (
  SELECT 
    COUNT(CASE WHEN hospital_expire_flag = 1 THEN hadm_id END) AS deaths,
    COUNT(hadm_id) AS total_patients,
    AVG(anchor_age) AS mean_age,
    APPROX_QUANTILES(anchor_age, 1000)[OFFSET(500)] AS median_age
  FROM 
    patients_of_interest
)

-- Select summary statistics
SELECT 
  'In-hospital mortality rate' AS statistic,
  deaths / total_patients AS value
FROM 
  stats

UNION ALL

SELECT 
  'Mean age' AS statistic,
  mean_age AS value
FROM 
  stats

UNION ALL

SELECT 
  'Median age' AS statistic,
  median_age AS value
FROM 
  stats

UNION ALL

SELECT 
  'Count' AS statistic,
  COUNT(hadm_id) AS value
FROM 
  patients_of_interest;