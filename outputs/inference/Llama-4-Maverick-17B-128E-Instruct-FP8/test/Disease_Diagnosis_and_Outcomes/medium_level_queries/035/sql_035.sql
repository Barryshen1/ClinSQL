WITH 
-- Step 1: Cohort selection and GI bleed classification
cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    CASE 
      WHEN dicd.icd_code LIKE 'K25%' OR dicd.icd_code LIKE 'K26%' OR dicd.icd_code LIKE 'K27%' THEN 'Upper GI Bleed'
      WHEN dicd.icd_code LIKE 'K92.0%' OR dicd.icd_code LIKE 'K92.1%' OR dicd.icd_code LIKE 'K92.2%' THEN 'Lower GI Bleed'
      ELSE NULL
    END AS gi_bleed_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE 
    p.gender = 'F' AND p.anchor_age BETWEEN 69 AND 79
),
-- Step 2: Calculate hospital LOS and in-hospital mortality
hospital_outcomes AS (
  SELECT 
    subject_id,
    hadm_id,
    gi_bleed_type,
    DATETIME_DIFF(dischtime, admittime, DAY) AS hospital_los,
    CASE WHEN deathtime IS NOT NULL AND deathtime <= dischtime THEN 1 ELSE 0 END AS in_hospital_mortality
  FROM 
    cohort
),
-- Step 3: Determine ICU admission status and day-1 ICU status
icu_status AS (
  SELECT 
    c.hadm_id,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_admission,
    CASE WHEN i.intime <= DATETIME_ADD(c.admittime, INTERVAL 1 DAY) THEN 1 ELSE 0 END AS day1_icu
  FROM 
    cohort c
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i ON c.hadm_id = i.hadm_id
),
-- Step 4: Grouping and aggregation
final AS (
  SELECT 
    gi_bleed_type,
    CASE 
      WHEN hospital_los BETWEEN 1 AND 2 THEN '1-2 days'
      WHEN hospital_los BETWEEN 3 AND 5 THEN '3-5 days'
      WHEN hospital_los BETWEEN 6 AND 9 THEN '6-9 days'
      WHEN hospital_los >= 10 THEN '>=10 days'
      ELSE NULL
    END AS los_category,
    day1_icu,
    COUNT(*) AS total_patients,
    SUM(in_hospital_mortality) AS total_deaths,
    SUM(icu_admission) AS total_icu_admissions
  FROM 
    hospital_outcomes ho
  JOIN 
    icu_status i ON ho.hadm_id = i.hadm_id
  WHERE 
    gi_bleed_type IS NOT NULL
  GROUP BY 
    gi_bleed_type, los_category, day1_icu
)
SELECT 
  gi_bleed_type,
  los_category,
  day1_icu,
  total_patients,
  (total_deaths / total_patients) * 100 AS in_hospital_mortality_rate,
  (total_icu_admissions / total_patients) * 100 AS icu_admission_rate
FROM 
  final
ORDER BY 
  gi_bleed_type, los_category, day1_icu;