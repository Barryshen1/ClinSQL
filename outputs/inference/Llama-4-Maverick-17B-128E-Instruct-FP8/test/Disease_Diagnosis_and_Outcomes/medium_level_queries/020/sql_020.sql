WITH 
-- Step 1: Identify sepsis patients (excluding septic shock)
sepsis_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%Sepsis%' AND d.icd_version = 9 AND diag.long_title NOT LIKE '%Shock%'
  UNION DISTINCT
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%Septic%' AND d.icd_version = 10 AND diag.long_title NOT LIKE '%Shock%'
),

-- Step 2 & 3: Filter patients, determine in-hospital mortality, and days-to-death
patient_data AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.deathtime,
    a.dischtime,
    p.dod,
    a.hospital_expire_flag,
    DATE_DIFF(COALESCE(a.deathtime, a.dischtime), a.admittime, DAY) AS los,
    DATE_DIFF(COALESCE(p.dod, a.dischtime), a.admittime, DAY) AS days_to_death
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM sepsis_patients)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
),

-- Step 4 & 5: Determine LOS category and day-1 ICU status
icu_status AS (
  SELECT 
    i.hadm_id,
    i.intime,
    i.outtime,
    icu.first_careunit,
    ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) AS icu_seq
  FROM `physionet-data.mimiciv_3_1_hosp.transfers` i
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON i.hadm_id = icu.hadm_id AND i.intime = icu.intime
),

-- Aggregate data
final_data AS (
  SELECT 
    pd.hadm_id,
    pd.los,
    pd.hospital_expire_flag,
    pd.days_to_death,
    CASE 
      WHEN pd.los <= 3 THEN '≤3'
      WHEN pd.los BETWEEN 4 AND 6 THEN '4–6'
      WHEN pd.los BETWEEN 7 AND 10 THEN '7–10'
      ELSE '>10'
    END AS los_category,
    icu.first_careunit AS day1_icu_status
  FROM patient_data pd
  LEFT JOIN icu_status icu ON pd.hadm_id = icu.hadm_id AND icu.icu_seq = 1
)

-- Report in-hospital mortality (%) by LOS and day-1 ICU status, plus median days-to-death
SELECT 
  los_category,
  day1_icu_status,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS in_hospital_deaths,
  SUM(hospital_expire_flag) / COUNT(*) * 100 AS in_hospital_mortality_pct,
  APPROX_QUANTILES(days_to_death, 100)[OFFSET(50)] AS median_days_to_death
FROM final_data
GROUP BY los_category, day1_icu_status
ORDER BY los_category, day1_icu_status;