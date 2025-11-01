WITH 
-- Filter patients of interest
patients_of_interest AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND a.admission_type = 'Emergency'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.icd_code LIKE '410%'
    )
),

-- Identify Troponin I lab results
troponin_i_results AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    CASE 
      WHEN l.valuenum <= 0.04 THEN 'normal'
      WHEN l.valuenum BETWEEN 0.04 AND 0.40 THEN 'borderline'
      WHEN l.valuenum >= 0.40 THEN 'elevated'
      ELSE 'unknown'
    END AS troponin_level
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON 
    l.itemid = d.itemid
  WHERE 
    d.label = 'Troponin I'
    AND l.valuenum IS NOT NULL
)

-- Calculate distribution statistics
SELECT 
  troponin_level,
  COUNT(DISTINCT hadm_id) AS count,
  COUNT(DISTINCT hadm_id) * 100.0 / SUM(COUNT(DISTINCT hadm_id)) OVER () AS percentage,
  AVG(valuenum) AS mean,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) OVER () AS median,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) OVER () AS q1,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) OVER () AS q3,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) OVER () - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) OVER () AS iqr
FROM 
  troponin_i_results
WHERE 
  hadm_id IN (SELECT hadm_id FROM patients_of_interest)
GROUP BY 
  troponin_level;