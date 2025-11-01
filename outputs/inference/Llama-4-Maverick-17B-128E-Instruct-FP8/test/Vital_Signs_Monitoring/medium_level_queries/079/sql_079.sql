WITH 
-- Filter patients
patients_filtered AS (
  SELECT subject_id, gender, anchor_age 
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 40 AND 50
),

-- Get ICU stays with intime and outtime
icustays_filtered AS (
  SELECT stay_id, subject_id, hadm_id, intime, outtime 
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Calculate mean SBP for each stay during the first 48 hours
sbp_mean AS (
  SELECT 
    ce.stay_id, 
    AVG(ce.valuenum) AS mean_sbp
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    icustays_filtered icu ON ce.stay_id = icu.stay_id
  WHERE 
    ce.itemid IN (220050, 220179, 51)  -- SBP itemids
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  GROUP BY 
    ce.stay_id
),

-- Categorize mean SBP
sbp_categories AS (
  SELECT 
    stay_id,
    CASE 
      WHEN mean_sbp < 140 THEN '<140'
      WHEN mean_sbp BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category
  FROM 
    sbp_mean
),

-- Identify MI cases
mi_cases AS (
  SELECT DISTINCT 
    hadm_id 
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd ON diag.icd_code = d_icd.icd_code AND diag.icd_version = d_icd.icd_version
  WHERE 
    d_icd.long_title LIKE '%Myocardial Infarction%'  -- Simplified MI identification
),

-- Main analysis
analysis AS (
  SELECT 
    sc.sbp_category,
    COUNT(DISTINCT icu.stay_id) AS total_stays,
    COUNT(DISTINCT CASE WHEN mi.hadm_id IS NOT NULL THEN icu.hadm_id END) AS mi_count
  FROM 
    icustays_filtered icu
  INNER JOIN 
    patients_filtered p ON icu.subject_id = p.subject_id
  INNER JOIN 
    sbp_categories sc ON icu.stay_id = sc.stay_id
  LEFT JOIN 
    mi_cases mi ON icu.hadm_id = mi.hadm_id
  GROUP BY 
    sc.sbp_category
)

-- Final output
SELECT 
  sbp_category,
  total_stays,
  mi_count,
  (mi_count / total_stays) * 100 AS mi_rate_percent,
  (total_stays / (SELECT SUM(total_stays) FROM analysis)) * 100 AS percent_of_total_stays
FROM 
  analysis
ORDER BY 
  sbp_category;