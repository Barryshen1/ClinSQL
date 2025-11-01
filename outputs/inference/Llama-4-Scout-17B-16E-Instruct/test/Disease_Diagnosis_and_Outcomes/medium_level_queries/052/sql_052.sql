WITH 
-- Patient cohort
patients_cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' AND 
    p.anchor_age BETWEEN 52 AND 62
),

-- ICU stay
icu_stay AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    CASE 
      WHEN i.stay_id IS NOT NULL THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_non_icu
  FROM 
    patients_cohort pc
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i ON pc.hadm_id = i.hadm_id
),

-- LOS categorization
los_category AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) <= 5 THEN 'LOS_leq_5'
      ELSE 'LOS_gt_5'
    END AS los_category
  FROM 
    patients_cohort
),

-- Comorbidity count
comorbidity_count AS (
  SELECT 
    subject_id,
    COUNT(DISTINCT icd_code) AS comorbidity_count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY 
    subject_id
),

-- CKD and diabetes prevalence
prevalence AS (
  SELECT 
    subject_id,
    hadm_id,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code 
        WHERE d.subject_id = p.subject_id AND dd.long_title LIKE '%CKD%'
      ) THEN 1 
      ELSE 0 
    END AS ckd,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code 
        WHERE d.subject_id = p.subject_id AND dd.long_title LIKE '%Diabetes%'
      ) THEN 1 
      ELSE 0 
    END AS diabetes
  FROM 
    patients_cohort p
),

-- Final calculations
final AS (
  SELECT 
    icu.icu_non_icu,
    los.los_category,
    NTILE(3) OVER (ORDER BY cc.comorbidity_count) AS comorbidity_tertile,
    CASE 
      WHEN pc.hospital_expire_flag = 1 OR pc.deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS in_hospital_mortality,
    COALESCE(pre.ckd, 0) AS ckd,
    COALESCE(pre.diabetes, 0) AS diabetes
  FROM 
    patients_cohort pc
  JOIN 
    icu_stay icu ON pc.hadm_id = icu.hadm_id AND pc.subject_id = icu.subject_id
  JOIN 
    los_category los ON pc.hadm_id = los.hadm_id
  JOIN 
    comorbidity_count cc ON pc.subject_id = cc.subject_id
  LEFT JOIN 
    prevalence pre ON pc.hadm_id = pre.hadm_id AND pc.subject_id = pre.subject_id
)

-- Grouping and reporting
SELECT 
  icu_non_icu,
  los_category,
  comorbidity_tertile,
  AVG(in_hospital_mortality) * 100 AS in_hospital_mortality_pct,
  AVG(ckd) * 100 AS ckd_prevalence_pct,
  AVG(diabetes) * 100 AS diabetes_prevalence_pct
FROM 
  final
GROUP BY 
  icu_non_icu,
  los_category,
  comorbidity_tertile;