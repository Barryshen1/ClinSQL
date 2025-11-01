WITH 
-- Step 1: Identify patients with AMI and ICU stay
ami_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 88 AND 98
  AND d_diag.long_title LIKE '%Acute myocardial infarction%'
),

-- Step 2: Calculate composite risk percentile (simplified example)
composite_risk AS (
  SELECT subject_id, hadm_id, 
         -- Example: Using a simple lab value (e.g., creatinine) as a proxy for risk
         PERCENT_RANK() OVER (ORDER BY MAX(valuenum)) AS risk_percentile
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label = 'Creatinine')
  GROUP BY subject_id, hadm_id
),

-- Step 3: Calculate outcomes
outcomes AS (
  SELECT a.subject_id, a.hadm_id,
         -- 30-day Mortality
         CASE WHEN a.dischtime <= p.dod AND DATE_DIFF(p.dod, a.dischtime, DAY) <= 30 THEN 1 ELSE 0 END AS mortality_30d,
         -- AKI (simplified, actual implementation may vary based on KDIGO criteria)
         MAX(CASE WHEN dl.label = 'Creatinine' AND le.valuenum > 2 THEN 1 ELSE 0 END) AS aki,
         -- ARDS (simplified, might require more complex logic or additional data)
         MAX(CASE WHEN d_diag.long_title LIKE '%Acute respiratory distress syndrome%' THEN 1 ELSE 0 END) AS ards
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON a.hadm_id = le.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON le.itemid = dl.itemid
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  GROUP BY a.subject_id, a.hadm_id, a.dischtime, p.dod
)

-- Final Query
SELECT 
  AVG(c.risk_percentile) AS avg_composite_risk,
  AVG(o.mortality_30d) AS mortality_30d_rate,
  AVG(o.aki) AS aki_rate,
  AVG(o.ards) AS ards_rate,
  APPROX_QUANTILES(DATE_DIFF(p.dod, a.dischtime, DAY), 1000)[OFFSET(500)] AS median_survival_days
FROM ami_patients ap
INNER JOIN composite_risk c ON ap.subject_id = c.subject_id AND ap.hadm_id = c.hadm_id
INNER JOIN outcomes o ON ap.hadm_id = o.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ap.hadm_id = a.hadm_id
LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON ap.subject_id = p.subject_id
WHERE o.mortality_30d = 1;  -- Filter to decedents for survival analysis;