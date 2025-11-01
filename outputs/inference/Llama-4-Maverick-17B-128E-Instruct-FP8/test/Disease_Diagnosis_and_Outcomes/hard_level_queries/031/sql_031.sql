WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 85 AND 95
  AND a.hadm_id IN (
    SELECT hadm_id 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
    WHERE dicd.long_title LIKE '%Asthma%' AND dicd.long_title LIKE '%exacerbation%'
  )
),

-- Step 2: Calculate Charlson Comorbidity Index (CCI)
cci_scores AS (
  SELECT a.hadm_id, 
         SUM(CASE 
           WHEN dicd.icd_code IN ('410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9') THEN 1  -- Myocardial infarction
           WHEN dicd.icd_code LIKE '428%' THEN 1  -- Congestive heart failure
           WHEN dicd.icd_code LIKE '4%' AND dicd.icd_code NOT IN ('401.0', '401.1', '401.9') THEN 1  -- Peripheral vascular disease
           WHEN dicd.icd_code LIKE '430%' OR dicd.icd_code LIKE '431%' OR dicd.icd_code LIKE '432%' OR dicd.icd_code LIKE '433%' OR dicd.icd_code LIKE '434%' OR dicd.icd_code LIKE '435%' OR dicd.icd_code LIKE '436%' OR dicd.icd_code LIKE '437%' THEN 1  -- Cerebrovascular disease
           WHEN dicd.icd_code LIKE '440%' THEN 1  -- Peripheral vascular disease
           WHEN dicd.icd_code LIKE '442%' THEN 1  -- Peripheral vascular disease
           WHEN dicd.icd_code LIKE '443.9' THEN 1  -- Peripheral vascular disease
           WHEN dicd.icd_code LIKE '585%' THEN 2  -- Chronic kidney disease
           WHEN dicd.icd_code LIKE '250%' THEN 1  -- Diabetes
           WHEN dicd.icd_code LIKE '491%' OR dicd.icd_code LIKE '492%' OR dicd.icd_code LIKE '493%' OR dicd.icd_code LIKE '496%' THEN 1  -- Chronic pulmonary disease
           WHEN dicd.icd_code LIKE '155%' THEN 1  -- Liver disease (mild)
           WHEN dicd.long_title LIKE '%liver cirrhosis%' OR dicd.long_title LIKE '%liver failure%' THEN 3  -- Liver disease (moderate to severe)
           WHEN dicd.icd_code LIKE '140%' OR dicd.icd_code LIKE '141%' OR dicd.icd_code LIKE '142%' OR dicd.icd_code LIKE '143%' OR dicd.icd_code LIKE '144%' OR dicd.icd_code LIKE '145%' OR dicd.icd_code LIKE '146%' OR dicd.icd_code LIKE '147%' OR dicd.icd_code LIKE '148%' OR dicd.icd_code LIKE '149%' THEN 2  -- Cancer
           WHEN dicd.icd_code LIKE '196%' OR dicd.icd_code LIKE '197%' OR dicd.icd_code LIKE '198%' OR dicd.icd_code LIKE '199%' THEN 2  -- Metastatic cancer
           WHEN dicd.icd_code LIKE '042%' OR dicd.icd_code LIKE '043%' OR dicd.icd_code LIKE '044%' THEN 6  -- AIDS/HIV
           ELSE 0 
           END) AS cci
  FROM cohort a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  GROUP BY a.hadm_id
),

-- Step 3: Stratify by CCI into quartiles
quartiles AS (
  SELECT hadm_id, cci,
         NTILE(4) OVER (ORDER BY cci) AS quartile
  FROM cci_scores
),

-- Step 4: Determine outcomes
outcomes AS (
  SELECT q.hadm_id, q.cci, q.quartile,
         a.hospital_expire_flag AS in_hospital_mortality,
         CASE 
           WHEN d.icd_code IN ('410.0', '410.1', '410.2', '410.3', '410.4', '410.5', '410.6', '410.7', '410.8', '410.9', 
                              '427.5', '427.31', '427.32', '427.41', '427.42', '427.5', '785.0', '785.1') THEN 1 
           ELSE 0 
         END AS cardiovascular_complication,
         CASE 
           WHEN d.icd_code LIKE '430%' OR d.icd_code LIKE '431%' OR d.icd_code LIKE '432%' OR d.icd_code LIKE '433%' OR d.icd_code LIKE '434%' OR d.icd_code LIKE '435%' OR d.icd_code LIKE '436%' OR d.icd_code LIKE '437%' THEN 1 
           ELSE 0 
         END AS neurologic_complication
  FROM quartiles q
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON q.hadm_id = a.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON q.hadm_id = d.hadm_id
)

-- Final analysis
SELECT quartile,
       COUNT(DISTINCT hadm_id) AS total_patients,
       SUM(in_hospital_mortality) / COUNT(DISTINCT hadm_id) AS in_hospital_mortality_rate,
       SUM(cardiovascular_complication) / COUNT(DISTINCT hadm_id) AS cardiovascular_complication_rate,
       SUM(neurologic_complication) / COUNT(DISTINCT hadm_id) AS neurologic_complication_rate
FROM outcomes
GROUP BY quartile
ORDER BY quartile;