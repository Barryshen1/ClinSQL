WITH qualifying_admissions AS (
  SELECT DISTINCT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime,
    p.gender, 
    p.anchor_age, 
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410%' OR d.icd_code LIKE '786.5%'))
      OR 
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'R07%'))
    )
    AND CAST(p.anchor_age AS INT64) + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 35 AND 45
),
first_troponin AS (
  SELECT 
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN qualifying_admissions qa 
    ON le.hadm_id = qa.hadm_id
  WHERE le.itemid = 3655
    AND le.valuenum IS NOT NULL
    AND le.charttime >= qa.admittime
)
SELECT 
  CASE 
    WHEN valuenum < 0.014 THEN 'normal'
    WHEN valuenum < 0.1 THEN 'borderline'
    ELSE 'myocardial injury'
  END AS category,
  COUNT(*) AS count
FROM first_troponin
WHERE rn = 1
GROUP BY category
ORDER BY category;