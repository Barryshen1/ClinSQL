WITH 
-- Step 1: Identify ARDS patients within the age range
ards_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 71 AND 81
  AND dicd.long_title LIKE '%Acute respiratory distress syndrome%'
),

-- Step 2: Calculate instability score (simplified, e.g., using SOFA score components)
instability_scores AS (
  SELECT i.stay_id, 
         -- Simplified example; actual calculation depends on the score definition
         MAX(CASE WHEN di.label = 'Platelet Count' THEN ce.valuenum ELSE NULL END) AS platelet_count,
         MAX(CASE WHEN di.label = 'Creatinine' THEN ce.valuenum ELSE NULL END) AS creatinine
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN ards_patients ap ON i.hadm_id = ap.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON i.stay_id = ce.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE DATETIME_DIFF(ce.charttime, i.intime, HOUR) <= 72
  GROUP BY i.stay_id
),

-- Step 3: Calculate 90th percentile instability score
percentile_score AS (
  SELECT APPROX_QUANTILES(platelet_count + creatinine, 100)[OFFSET(90)] AS threshold
  FROM instability_scores
),

-- Step 4: Compare outcomes for patients above threshold
outcomes AS (
  SELECT 
    CASE WHEN (iso.platelet_count + iso.creatinine) >= ps.threshold THEN 'Above' ELSE 'Below' END AS threshold_group,
    a.hospital_expire_flag AS mortality,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los,
    i.los AS icu_los
  FROM instability_scores iso
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON iso.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  CROSS JOIN percentile_score ps
)

-- Final output
SELECT 
  threshold_group,
  COUNT(*) AS num_patients,
  AVG(mortality) AS mortality_rate,
  AVG(hospital_los) AS avg_hospital_los,
  AVG(icu_los) AS avg_icu_los
FROM outcomes
GROUP BY threshold_group;