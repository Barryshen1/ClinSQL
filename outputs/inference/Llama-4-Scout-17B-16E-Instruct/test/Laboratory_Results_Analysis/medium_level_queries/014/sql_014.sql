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
    p.anchor_age BETWEEN 79 AND 89
    AND p.gender = 'M'
),

-- Identify ACS admissions
acs_admissions AS (
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code LIKE '410%'
),

-- Troponin T lab events
troponin_t_events AS (
  SELECT 
    le.subject_id, 
    le.hadm_id, 
    le.charttime, 
    le.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
      ON le.itemid = dli.itemid
  WHERE 
    dli.label = 'Troponin T'
    AND le.valuenum IS NOT NULL
)

-- Combine and categorize
SELECT 
  CASE 
    WHEN tt.valuenum < 0.01 THEN 'Normal'
    WHEN tt.valuenum BETWEEN 0.01 AND 0.1 THEN 'Borderline'
    ELSE 'Elevated'
  END AS troponin_t_category,
  COUNT(DISTINCT poi.hadm_id) AS count
FROM 
  patients_of_interest poi
JOIN 
  acs_admissions aa 
    ON poi.subject_id = aa.subject_id AND poi.hadm_id = aa.hadm_id
JOIN 
  troponin_t_events tt 
    ON poi.subject_id = tt.subject_id AND poi.hadm_id = tt.hadm_id
WHERE 
  tt.charttime = (SELECT MIN(charttime) FROM troponin_t_events tte 
                   WHERE tte.subject_id = tt.subject_id AND tte.hadm_id = tt.hadm_id)
GROUP BY 
  troponin_t_category
ORDER BY 
  troponin_t_category;