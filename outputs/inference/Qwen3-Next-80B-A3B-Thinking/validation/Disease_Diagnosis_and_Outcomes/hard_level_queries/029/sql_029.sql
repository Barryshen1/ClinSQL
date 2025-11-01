WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    p.anchor_age, 
    p.gender, 
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND dd.long_title LIKE '%pneumonia%'
),

quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY anchor_age) AS risk_quintile
  FROM cohort
),

survivors AS (
  SELECT 
    q.*,
    CASE 
      WHEN q.dod IS NULL OR q.dod > DATE_ADD(q.admittime, INTERVAL 30 DAY) 
        THEN 1 
      ELSE 0 
    END as survived_30d,
    DATE_DIFF(q.dischtime, q.admittime, DAY) as los
  FROM quintiles q
),

cv_complications AS (
  SELECT 
    d.hadm_id, 
    1 as cv_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    dd.long_title LIKE '%myocardial infarction%' 
    OR dd.long_title LIKE '%heart failure%' 
    OR dd.long_title LIKE '%acute coronary syndrome%'
    OR dd.long_title LIKE '%cardiac arrest%'
    OR dd.long_title LIKE '%arrhythmia%'
    OR dd.long_title LIKE '%cardiomyopathy%'
    OR dd.long_title LIKE '%coronary artery disease%'
    OR dd.long_title LIKE '%angina%'
  GROUP BY d.hadm_id
),

neuro_complications AS (
  SELECT 
    d.hadm_id, 
    1 as neuro_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    dd.long_title LIKE '%stroke%' 
    OR dd.long_title LIKE '%seizure%' 
    OR dd.long_title LIKE '%encephalopathy%' 
    OR dd.long_title LIKE '%coma%'
    OR dd.long_title LIKE '%neurological%'
  GROUP BY d.hadm_id
),

mortality AS (
  SELECT 
    risk_quintile,
    AVG(CASE WHEN survived_30d = 0 THEN 1 ELSE 0 END) as mortality_rate
  FROM survivors
  GROUP BY risk_quintile
),

cv_rates AS (
  SELECT 
    q.risk_quintile,
    AVG(CASE WHEN cv.cv_complication = 1 THEN 1 ELSE 0 END) as cv_rate
  FROM quintiles q
  LEFT JOIN cv_complications cv 
    ON q.hadm_id = cv.hadm_id
  GROUP BY q.risk_quintile
),

neuro_rates AS (
  SELECT 
    q.risk_quintile,
    AVG(CASE WHEN n.neuro_complication = 1 THEN 1 ELSE 0 END) as neuro_rate
  FROM quintiles q
  LEFT JOIN neuro_complications n 
    ON q.hadm_id = n.hadm_id
  GROUP BY q.risk_quintile
),

median_los AS (
  SELECT 
    risk_quintile,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] as median_los
  FROM survivors
  WHERE survived_30d = 1
  GROUP BY risk_quintile
)

SELECT 
  m.risk_quintile,
  m.mortality_rate,
  cv.cv_rate,
  n.neuro_rate,
  ml.median_los
FROM mortality m
JOIN cv_rates cv 
  ON m.risk_quintile = cv.risk_quintile
JOIN neuro_rates n 
  ON m.risk_quintile = n.risk_quintile
JOIN median_los ml 
  ON m.risk_quintile = ml.risk_quintile
ORDER BY m.risk_quintile;