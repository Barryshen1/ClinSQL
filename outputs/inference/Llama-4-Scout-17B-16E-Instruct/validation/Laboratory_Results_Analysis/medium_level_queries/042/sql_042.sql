WITH 
-- Filter patients
patients_filtered AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND a.admission_type = 'Emergency'
    AND a.discharge_location LIKE '%chest pain%'
),

-- Identify troponin T lab results
troponin_results AS (
  SELECT 
    hadm_id,
    charttime,
    value,
    valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE 
    itemid = 4569  -- troponin T
    AND valuenum IS NOT NULL
),

-- Classify troponin T results
troponin_classified AS (
  SELECT 
    hadm_id,
    charttime,
    value,
    valuenum,
    CASE 
      WHEN valuenum < 0.01 THEN 'normal'
      WHEN valuenum BETWEEN 0.01 AND 0.1 THEN 'borderline'
      ELSE 'elevated'
    END AS troponin_category
  FROM 
    troponin_results
  WHERE 
    charttime = (SELECT MAX(charttime) FROM troponin_results t2 WHERE t2.hadm_id = troponin_results.hadm_id)
)

-- Calculate distribution and in-hospital mortality
SELECT 
  t.troponin_category,
  COUNT(t.hadm_id) AS count,
  COUNT(t.hadm_id) * 100.0 / SUM(COUNT(t.hadm_id)) OVER () AS percentage,
  SUM(CASE WHEN pf.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths,
  SUM(CASE WHEN pf.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(t.hadm_id) AS in_hospital_mortality_rate
FROM 
  patients_filtered pf
JOIN 
  troponin_classified t
ON 
  pf.hadm_id = t.hadm_id
GROUP BY 
  t.troponin_category
ORDER BY 
  t.troponin_category;