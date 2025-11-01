WITH 
-- Step 1: Identify patients with DVT
dvt_patients AS (
  SELECT DISTINCT p.subject_id, p.gender, EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 42 AND 52
  AND d_diag.long_title LIKE '%Deep vein thrombosis%'
),

-- Step 2: Calculate lab instability score for DVT patients
lab_instability AS (
  SELECT dvt.subject_id, 
         COUNT(CASE 
           WHEN (d_li.ref_range_lower IS NOT NULL AND l.valuenum < d_li.ref_range_lower) 
             OR (d_li.ref_range_upper IS NOT NULL AND l.valuenum > d_li.ref_range_upper) 
           THEN 1 END) AS instability_score
  FROM dvt_patients dvt
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON dvt.subject_id = l.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d_li ON l.itemid = d_li.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  WHERE l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY dvt.subject_id
),

-- Step 3: Calculate 95th percentile of lab instability score
percentile_95 AS (
  SELECT PERCENTILE_CONT(instability_score, 0.95) OVER () AS percentile_value
  FROM lab_instability
),

-- Step 4: Analyze patients >= 95th percentile
high_risk_patients AS (
  SELECT li.subject_id, 
         a.hospital_expire_flag, 
         DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
         icu.los AS icu_los
  FROM lab_instability li
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON li.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE li.instability_score >= (SELECT percentile_value FROM percentile_95 LIMIT 1)
)

-- Final analysis
SELECT 
  COUNT(CASE WHEN hospital_expire_flag = 1 THEN 1 END) / COUNT(*) AS mortality_rate,
  AVG(los_hours) AS mean_los_hours,
  AVG(icu_los) AS mean_icu_los
FROM high_risk_patients;