WITH ami_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'I21%' AND icd_version = 10
),
ami_admissions AS (
  SELECT 
    a.hadm_id, 
    a.admittime, 
    p.anchor_age, 
    p.anchor_year, 
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN ami_hadm am 
    ON a.hadm_id = am.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
),
hs_tnt_first AS (
  SELECT 
    a.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY l.charttime) AS rn
  FROM ami_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON a.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di 
    ON l.itemid = di.itemid
  WHERE di.label LIKE '%high%troponin%t%' 
    AND l.valueuom = 'ng/L'
    AND l.charttime >= a.admittime
    AND l.valuenum IS NOT NULL
)
SELECT 
  CASE 
    WHEN valuenum < 14 THEN 'normal'
    WHEN valuenum BETWEEN 14 AND 20 THEN 'borderline'
    WHEN valuenum > 20 THEN 'myocardial injury'
    ELSE 'unknown'
  END AS category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM hs_tnt_first
WHERE rn = 1
GROUP BY category;