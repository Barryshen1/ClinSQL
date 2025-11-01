WITH 
-- Get patient admissions with suspected ACS
acs_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.icd_code LIKE '410%'  -- Myocardial Infarction or suspected ACS
    )
),

-- Categorize Troponin T levels
troponin_levels AS (
  SELECT 
    a.hadm_id,
    CASE
      WHEN l.valuenum < 0.1 THEN 'Normal'
      WHEN l.valuenum BETWEEN 0.1 AND 1.0 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM 
    acs_admissions a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.hadm_id = l.hadm_id
  WHERE 
    l.itemid = 4569  -- Troponin T
    AND l.charttime = (
      SELECT MAX(charttime)
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
      WHERE le.hadm_id = l.hadm_id
      AND le.itemid = 4569
    )
)

-- Calculate counts, percentages, and average LOS
SELECT 
  t.troponin_category,
  COUNT(DISTINCT a.hadm_id) AS count_patients,
  COUNT(DISTINCT a.hadm_id) / SUM(COUNT(DISTINCT a.hadm_id)) OVER () AS percentage,
  AVG(DATE_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime))) AS avg_los
FROM 
  acs_admissions a
  JOIN troponin_levels t ON a.hadm_id = t.hadm_id
WHERE 
  a.dischtime IS NOT NULL AND a.admittime IS NOT NULL
GROUP BY 
  t.troponin_category;