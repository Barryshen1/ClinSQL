WITH patients AS (
  SELECT subject_id, gender, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' 
    AND anchor_age BETWEEN 53 AND 63
),
admissions AS (
  SELECT subject_id, hadm_id, admittime, dischtime, hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
diagnoses AS (
  SELECT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE icd.long_title LIKE '%angina%' OR icd.long_title LIKE '%infarct%'  -- ACS: unstable angina, AMI
),
acs_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM patients p
  JOIN admissions a ON p.subject_id = a.subject_id
  JOIN diagnoses diag ON a.hadm_id = diag.hadm_id
),
control_cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM patients p
  JOIN admissions a ON p.subject_id = a.subject_id
  LEFT JOIN diagnoses diag ON a.hadm_id = diag.hadm_id
  WHERE diag.hadm_id IS NULL  -- Admissions without ACS diagnosis
),
lab_items AS (
  SELECT itemid, category, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE category IN ('Chemistry', 'Blood Gases', 'Hematology', 'Coagulation', 'Urine')
),
critical_per_category AS (
  SELECT 
    le.hadm_id,
    li.category
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN lab_items li ON le.itemid = li.itemid
  JOIN admissions a ON le.hadm_id = a.hadm_id
  WHERE le.charttime >= a.admittime 
    AND le.charttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND le.valuenum IS NOT NULL
    AND (
      -- Electrolytes (e.g., K, Na, Cl, Ca, Mg)
      (li.category = 'Chemistry' AND (
        (li.label LIKE '%Potassium%' AND (le.valuenum < 3.0 OR le.valuenum > 6.0))
        OR (li.label LIKE '%Sodium%' AND (le.valuenum < 130 OR le.valuenum > 150))
        OR (li.label LIKE '%Chloride%' AND (le.valuenum < 95 OR le.valuenum > 110))
        OR (li.label LIKE '%Calcium%' AND (le.valuenum < 7.0 OR le.valuenum > 10.5))
        OR (li.label LIKE '%Magnesium%' AND (le.valuenum < 1.0 OR le.valuenum > 2.5))
      ))
      -- Renal (e.g., BUN, Creatinine)
      OR (li.category = 'Chemistry' AND (
        (li.label LIKE '%BUN%' AND le.valuenum > 50)
        OR (li.label LIKE '%Creatinine%' AND le.valuenum > 3.0)
      ))
      -- CBC (e.g., Hgb, Plt, WBC)
      OR (li.category = 'Hematology' AND (
        (li.label LIKE '%Hemoglobin%' AND (le.valuenum < 7.0 OR le.valuenum > 18.0))
        OR (li.label LIKE '%Platelet%' AND (le.valuenum < 50 OR le.valuenum > 1000))
        OR (li.label LIKE '%WBC%' AND (le.valuenum < 2.0 OR le.valuenum > 30.0))
      ))
      -- Cardiac (e.g., Troponin)
      OR (li.category = 'Chemistry' AND li.label LIKE '%Troponin%' AND le.valuenum > 0.4)
      -- Coagulation (e.g., INR, PTT)
      OR (li.category = 'Coagulation' AND (
        (li.label LIKE '%INR%' AND le.valuenum > 5.0)
        OR (li.label LIKE '%PTT%' AND le.valuenum > 100)
      ))
    )
  GROUP BY le.hadm_id, li.category
  HAVING COUNT(*) >= 1  -- At least one critical value per category
),
critical_labs AS (
  SELECT 
    hadm_id,
    COUNT(DISTINCT category) AS instability_score
  FROM critical_per_category
  GROUP BY hadm_id
),
scores AS (
  -- ACS scores
  SELECT 
    'ACS' AS cohort,
    ac.hadm_id,
    COALESCE(cl.instability_score, 0) AS instability_score,
    ac.hospital_expire_flag,
    DATE_DIFF(ac.dischtime, ac.admittime, DAY) AS los_days
  FROM acs_cohort ac
  LEFT JOIN critical_labs cl ON ac.hadm_id = cl.hadm_id
  
  UNION ALL
  
  -- Control scores
  SELECT 
    'Control' AS cohort,
    cc.hadm_id,
    COALESCE(cl.instability_score, 0) AS instability_score,
    cc.hospital_expire_flag,
    DATE_DIFF(cc.dischtime, cc.admittime, DAY) AS los_days
  FROM control_cohort cc
  LEFT JOIN critical_labs cl ON cc.hadm_id = cl.hadm_id
),
quartiles AS (
  SELECT 
    cohort,
    instability_score,
    hospital_expire_flag,
    los_days,
    NTILE(4) OVER (PARTITION BY cohort ORDER BY instability_score) AS quartile
  FROM scores
),
aggregated AS (
  SELECT 
    cohort,
    quartile,
    COUNT(*) AS n_patients,
    SUM(hospital_expire_flag) AS n_deaths,
    AVG(los_days) AS avg_los_days,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100 AS mortality_pct
  FROM quartiles
  GROUP BY cohort, quartile
),
critical_rate AS (
  SELECT 
    cohort,
    COUNT(*) AS n_patients,
    SAFE_DIVIDE(COUNTIF(instability_score >= 3), COUNT(*)) * 100 AS high_instability_pct
  FROM scores
  GROUP BY cohort
)
-- Main results: quartiles with outcomes
SELECT 
  cohort,
  CAST(quartile AS STRING) AS quartile,
  n_patients,
  ROUND(mortality_pct, 2) AS mortality_pct,
  ROUND(avg_los_days, 2) AS avg_los_days
FROM aggregated
ORDER BY cohort, quartile

UNION ALL

-- Comparison: high instability rates (≥3 categories)
SELECT 
  cohort,
  'Overall' AS quartile,
  n_patients,
  ROUND(high_instability_pct, 2) AS mortality_pct,  -- Repurposed for rate
  NULL AS avg_los_days
FROM critical_rate
ORDER BY cohort;