WITH qualifying_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND di.seq_num = 1
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'R07%') 
      OR 
      (di.icd_version = 9 AND di.icd_code LIKE '7865%')
    )
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 61 AND 71
),
initial_tnt AS (
  SELECT 
    qa.hadm_id, 
    le.charttime, 
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY qa.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM qualifying_admissions qa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON qa.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
    ON le.itemid = dli.itemid
  WHERE LOWER(dli.label) LIKE '%troponin-t%'
    AND dli.category = 'Chemistry'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.charttime >= qa.admittime
)
SELECT 
  category,
  cnt AS n,
  ROUND(cnt * 100.0 / SUM(cnt) OVER (), 2) AS percent
FROM (
  SELECT 
    CASE 
      WHEN valuenum < 0.014 THEN 'normal'
      WHEN valuenum < 0.050 THEN 'borderline'
      ELSE 'myocardial injury'
    END AS category,
    COUNT(*) AS cnt
  FROM initial_tnt
  WHERE rn = 1
  GROUP BY 1
)
ORDER BY 
  CASE category 
    WHEN 'normal' THEN 1 
    WHEN 'borderline' THEN 2 
    ELSE 3 
  END;