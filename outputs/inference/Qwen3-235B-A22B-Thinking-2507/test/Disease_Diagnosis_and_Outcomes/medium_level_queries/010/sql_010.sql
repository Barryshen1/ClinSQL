WITH ami_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE d.seq_num = 1  -- primary diagnosis
    AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')
    AND p.gender = 'M'
),

-- Calculate age at admission and filter by age range
age_filtered AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    -- Calculate age at admission
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM ami_patients
  WHERE anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 78 AND 88
),

-- Exclude patients with shock or respiratory failure
no_shock_rf AS (
  SELECT 
    af.subject_id,
    af.hadm_id,
    af.admittime,
    af.dischtime
  FROM age_filtered af
  WHERE NOT EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    WHERE d.hadm_id = af.hadm_id
      AND (
        d.icd_code LIKE 'R57%'  -- Shock codes
        OR d.icd_code LIKE 'J96%'  -- Respiratory failure codes
      )
  )
),

-- Calculate LOS and mortality
los_mortality AS (
  SELECT 
    ns.subject_id,
    ns.hadm_id,
    ns.admittime,
    ns.dischtime,
    DATETIME_DIFF(ns.dischtime, ns.admittime, HOUR) / 24.0 AS los_days,
    a.hospital_expire_flag AS died_in_hospital
  FROM no_shock_rf ns
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ns.hadm_id = a.hadm_id
),

-- Calculate comorbidities (simplified Charlson)
comorbidities AS (
  SELECT 
    lm.subject_id,
    lm.hadm_id,
    lm.los_days,
    lm.died_in_hospital,
    -- Count distinct comorbidities
    (MAX(CASE WHEN d.icd_code LIKE 'I10%' OR d.icd_code LIKE 'I11%' OR d.icd_code LIKE 'I12%' OR d.icd_code LIKE 'I13%' OR d.icd_code LIKE 'I15%' THEN 1 ELSE 0 END) +
     MAX(CASE WHEN d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' THEN 1 ELSE 0 END) +
     MAX(CASE WHEN d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) +
     MAX(CASE WHEN d.icd_code LIKE 'I20%' OR d.icd_code LIKE 'I25%' THEN 1 ELSE 0 END) +
     MAX(CASE WHEN d.icd_code LIKE 'J40%' OR d.icd_code LIKE 'J41%' OR d.icd_code LIKE 'J42%' OR d.icd_code LIKE 'J43%' OR d.icd_code LIKE 'J44%' OR d.icd_code LIKE 'J45%' OR d.icd_code LIKE 'J46%' OR d.icd_code LIKE 'J47%' THEN 1 ELSE 0 END)) AS charlson_count,
    MAX(CASE WHEN d.icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    MAX(CASE WHEN d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%' THEN 1 ELSE 0 END) AS has_diabetes
  FROM los_mortality lm
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON lm.hadm_id = d.hadm_id
    AND d.seq_num > 1  -- Exclude primary diagnosis (which is AMI)
  GROUP BY lm.subject_id, lm.hadm_id, lm.los_days, lm.died_in_hospital
),

-- Calculate comorbidity burden groups (tertiles)
comorbidity_groups AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY charlson_count) AS comorbidity_burden_group
  FROM comorbidities
),

-- Calculate LOS quartiles
los_quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile
  FROM comorbidity_groups
)

-- Final result: mortality by LOS quartile and comorbidity burden
SELECT 
  los_quartile,
  comorbidity_burden_group,
  COUNT(*) AS total_patients,
  SUM(died_in_hospital) AS deaths,
  AVG(died_in_hospital) AS mortality_rate,
  -- 95% CI for mortality rate
  GREATEST(0, AVG(died_in_hospital) - 1.96 * SQRT(AVG(died_in_hospital) * (1 - AVG(died_in_hospital)) / COUNT(*))) AS ci_lower,
  LEAST(1, AVG(died_in_hospital) + 1.96 * SQRT(AVG(died_in_hospital) * (1 - AVG(died_in_hospital)) / COUNT(*))) AS ci_upper,
  -- CKD prevalence
  AVG(has_ckd) AS ckd_prevalence,
  -- Diabetes prevalence
  AVG(has_diabetes) AS diabetes_prevalence
FROM los_quartiles
GROUP BY los_quartile, comorbidity_burden_group
ORDER BY los_quartile, comorbidity_burden_group;