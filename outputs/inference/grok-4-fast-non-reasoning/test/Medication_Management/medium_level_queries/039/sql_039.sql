WITH qualifying_patients AS (
  -- Select patients: males 52-62
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
t2dm_admissions AS (
  -- Admissions with T2DM (E11.* ICD-10)
  SELECT DISTINCT di.hadm_id, di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON di.icd_code = icd.icd_code AND di.icd_version = icd.icd_version
  INNER JOIN qualifying_patients qp ON di.subject_id = qp.subject_id
  WHERE di.icd_version = '10'
    AND di.icd_code LIKE 'E11.%'
),
hf_admissions AS (
  -- Admissions with heart failure (I50.* ICD-10)
  SELECT DISTINCT di.hadm_id, di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON di.icd_code = icd.icd_code AND di.icd_version = icd.icd_version
  INNER JOIN qualifying_patients qp ON di.subject_id = qp.subject_id
  WHERE di.icd_version = '10'
    AND di.icd_code LIKE 'I50.%'
),
qualifying_admissions AS (
  -- Intersect: admissions with BOTH T2DM and HF, inpatient only
  SELECT DISTINCT ta.hadm_id, ta.subject_id
  FROM t2dm_admissions ta
  INNER JOIN hf_admissions ha ON ta.hadm_id = ha.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON ta.hadm_id = a.hadm_id
  WHERE a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT', 'OBSERVATION')
),
icu_stays AS (
  -- First ICU stay per qualifying admission
  SELECT hadm_id, subject_id, stay_id, intime, outtime,
         ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN qualifying_admissions qa ON i.hadm_id = qa.hadm_id
  WHERE i.first_careunit IS NOT NULL  -- Valid ICU stay
),
glp1_events AS (
  -- Injectable GLP-1 administrations in ICU (itemids from d_items; e.g., 227689=semaglutide, 50075=liraglutide; expand as needed)
  SELECT i.hadm_id, i.stay_id, i.starttime
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  INNER JOIN icu_stays s ON i.stay_id = s.stay_id AND s.rn = 1
  WHERE i.itemid IN (225910,  -- semaglutide injection placeholder; verify/add via d_items
                     225912,  -- placeholder for another GLP-1 (e.g., 227689, 50075 for liraglutide)
                     -- Add dulaglutide (e.g., 228295), exenatide, etc.
                    )
    AND i.amount > 0
    AND i.ordercategoryname LIKE '%Endocrine%'  -- Better filter for GLP-1s
),
window_prevalence AS (
  SELECT 
    'First 24h' AS time_window,
    COUNT(DISTINCT ge.hadm_id) AS num_with_glp1,
    COUNT(DISTINCT s.hadm_id) AS total_admissions,
    ROUND(COUNT(DISTINCT ge.hadm_id) * 100.0 / COUNT(DISTINCT s.hadm_id), 2) AS prevalence_pct
  FROM icu_stays s
  LEFT JOIN glp1_events ge ON s.stay_id = ge.stay_id 
    AND ge.starttime >= s.intime 
    AND ge.starttime < TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
  WHERE s.rn = 1
  
  UNION ALL
  
  SELECT 
    'Final 48h' AS time_window,
    COUNT(DISTINCT ge.hadm_id) AS num_with_glp1,
    COUNT(DISTINCT s.hadm_id) AS total_admissions,
    ROUND(COUNT(DISTINCT ge.hadm_id) * 100.0 / COUNT(DISTINCT s.hadm_id), 2) AS prevalence_pct
  FROM icu_stays s
  LEFT JOIN glp1_events ge ON s.stay_id = ge.stay_id 
    AND ge.starttime >= TIMESTAMP_SUB(s.outtime, INTERVAL 48 HOUR) 
    AND ge.starttime < s.outtime
  WHERE s.rn = 1
)
-- Aggregate for changes
SELECT 
  MAX(CASE WHEN time_window = 'First 24h' THEN prevalence_pct END) AS first_24h_pct,
  MAX(CASE WHEN time_window = 'Final 48h' THEN prevalence_pct END) AS final_48h_pct,
  (MAX(CASE WHEN time_window = 'Final 48h' THEN prevalence_pct END) - 
   MAX(CASE WHEN time_window = 'First 24h' THEN prevalence_pct END)) AS absolute_change_pct,
  ROUND(
    ((MAX(CASE WHEN time_window = 'Final 48h' THEN prevalence_pct END) - 
      MAX(CASE WHEN time_window = 'First 24h' THEN prevalence_pct END)) / 
     NULLIF(MAX(CASE WHEN time_window = 'First 24h' THEN prevalence_pct END), 0)) * 100, 2
  ) AS relative_change_pct
FROM window_prevalence;