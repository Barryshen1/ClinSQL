WITH 
-- Step 1: Identify patients with pulmonary embolism
pe_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 53 AND 63
  AND diag.icd_code IN ('I26')  -- Simplified for ICD-10; adjust for ICD-9 if necessary
),

-- Step 2 & 3: Calculate lab instability score for PE patients in ICU
lab_instability AS (
  SELECT pe.subject_id, pe.hadm_id, 
         -- Example lab score calculation; adjust according to actual definition
         SUM(CASE WHEN di.label = 'Lactate' AND le.valuenum > 2 THEN 1 ELSE 0 END) AS lab_score
  FROM pe_patients pe
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON pe.hadm_id = icu.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON pe.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE DATETIME_DIFF(le.charttime, icu.intime, HOUR) BETWEEN 0 AND 72
  GROUP BY pe.subject_id, pe.hadm_id
),

-- Step 4: Calculate 75th percentile of lab instability score
percentile_threshold AS (
  SELECT APPROX_QUANTILES(lab_score, 100)[OFFSET(75)] AS threshold
  FROM lab_instability
),

-- Step 5: Analyze outcomes for patients >= threshold
outcomes AS (
  SELECT 
    a.hospital_expire_flag AS mortality,
    icu.los,
    -- Example critical lab rate; adjust definition as needed
    SUM(CASE WHEN di.label = 'Lactate' AND le.valuenum > 4 THEN 1 ELSE 0 END) AS critical_lab_count
  FROM lab_instability li
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON li.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON li.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON li.hadm_id = le.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON le.itemid = di.itemid
  WHERE li.lab_score >= (SELECT threshold FROM percentile_threshold)
  GROUP BY a.hospital_expire_flag, icu.los
)

-- Final query to report mortality (%), mean LOS, and critical-lab rates
SELECT 
  AVG(mortality) * 100 AS mortality_percent,
  AVG(los) AS mean_los_days,
  -- Compare critical-lab rates; this is a simplified example
  SUM(critical_lab_count) / COUNT(*) AS critical_lab_rate
FROM outcomes;