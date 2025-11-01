WITH 
-- Step 1: Identify patients with pneumonia
pneumonia_patients AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 73 AND 83 
  AND d_diag.long_title LIKE '%Pneumonia%'
),

-- Step 2: Calculate comorbidity score (using elixhauser comorbidity score as a proxy)
comorbidity_scores AS (
  SELECT hadm_id, COUNT(DISTINCT icd_code) AS elixhauser_comorbidity_count
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
  GROUP BY hadm_id
),

-- Step 3: Determine top-quartile comorbidity
top_quartile_comorbidity AS (
  SELECT hadm_id, 
         PERCENT_RANK() OVER (ORDER BY elixhauser_comorbidity_count) AS comorbidity_percentile
  FROM comorbidity_scores
),

-- Step 4: Calculate in-hospital mortality and major complications
cohort_outcomes AS (
  SELECT pp.subject_id, pp.hadm_id, pp.anchor_age, a.hospital_expire_flag,
         -- Define major complication (example: need for ventilation or vasopressors)
         -- For simplicity, let's assume major complication is having a procedure with icd_code starting with '5'
         EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc WHERE proc.hadm_id = pp.hadm_id AND proc.icd_code LIKE '5%') AS major_complication
  FROM pneumonia_patients pp
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON pp.hadm_id = a.hadm_id
  JOIN top_quartile_comorbidity tqc ON pp.hadm_id = tqc.hadm_id
  WHERE tqc.comorbidity_percentile >= 0.75  -- Top quartile
),

-- Step 5: Calculate median survival days for the cohort
survival_days AS (
  SELECT co.subject_id, co.hadm_id, 
         DATE_DIFF(CASE WHEN p.dod IS NULL THEN DATE('2022-01-01') ELSE p.dod END, a.dischtime, DAY) AS survival_days
  FROM cohort_outcomes co
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON co.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON co.subject_id = p.subject_id
)

-- Final query to get required statistics
SELECT 
  PERCENTILE_CONT(survival_days, 0.5) AS median_survival_days,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS in_hospital_mortality_percent,
  AVG(CASE WHEN major_complication THEN 1 ELSE 0 END) * 100 AS major_complication_percent
FROM cohort_outcomes
JOIN survival_days USING (subject_id, hadm_id);