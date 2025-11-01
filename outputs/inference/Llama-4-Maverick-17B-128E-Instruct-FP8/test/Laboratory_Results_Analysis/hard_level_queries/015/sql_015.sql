WITH 
-- Step 1: Identify male inpatients aged 49-59 with ischemic stroke
cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND dicd.long_title LIKE '%Ischemic stroke%'
),

-- Step 2: Calculate the 72-hour lab instability score
lab_instability AS (
  SELECT c.subject_id, c.hadm_id,
         COUNT(DISTINCT CASE WHEN le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper THEN le.itemid END) AS lab_instability_score
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON c.hadm_id = icu.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON icu.hadm_id = le.hadm_id
  WHERE DATETIME_DIFF(le.charttime, icu.intime, HOUR) BETWEEN 0 AND 72
    AND le.valuenum IS NOT NULL  -- Ensure valuenum is not null to avoid incorrect comparisons
  GROUP BY c.subject_id, c.hadm_id
),

-- Step 3: Determine the 75th percentile of the lab instability score
percentile_lab_instability AS (
  SELECT APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS percentile_75th
  FROM lab_instability
),

-- Step 4: Identify high-instability group and calculate LOS, mortality
high_instability_group AS (
  SELECT li.subject_id, li.hadm_id, li.lab_instability_score,
         icu.los, a.hospital_expire_flag AS mortality
  FROM lab_instability li
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON li.hadm_id = icu.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON li.hadm_id = a.hadm_id
  WHERE li.lab_instability_score >= (SELECT percentile_75th FROM percentile_lab_instability)
),

-- Step 5: Compare critical lab rates to age-matched controls
age_matched_controls AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.anchor_age BETWEEN 49 AND 59
    AND p.gender = 'M'
    AND a.hadm_id NOT IN (SELECT hadm_id FROM cohort)
)

-- Final analysis
SELECT 
  'High Instability' AS group_name,
  AVG(hig.los) AS avg_los,
  SUM(hig.mortality) / COUNT(hig.subject_id) AS mortality_rate
FROM high_instability_group hig
UNION ALL
SELECT 
  'Age-Matched Controls' AS group_name,
  AVG(icu.los) AS avg_los,
  SUM(a.hospital_expire_flag) / COUNT(amc.subject_id) AS mortality_rate
FROM age_matched_controls amc
INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON amc.hadm_id = icu.hadm_id
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON amc.hadm_id = a.hadm_id;