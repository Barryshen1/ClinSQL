WITH 
-- Step 1: Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admission_type = 'ELECTIVE'  -- Assuming AMI is elective, might need adjustment
    AND a.discharge_location NOT LIKE '%SNF%'  -- Exclude transfers to SNF
    AND a.admission_type IN ('URGENT', 'EMERGENCY')  -- Adjust for AMI if necessary
),

-- Step 2: Calculate medication complexity score (PLACEHOLDER: very simplified)
medication_complexity AS (
  SELECT 
    subject_id, 
    hadm_id, 
    COUNT(DISTINCT drug) AS medication_complexity_score
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY 
    subject_id, 
    hadm_id
),

-- Step 3: Merge patients with medication complexity
patients_with_complexity AS (
  SELECT 
    p.subject_id, 
    p.hadm_id, 
    p.anchor_age, 
    p.gender, 
    mc.medication_complexity_score,
    p.admittime,
    p.dischtime,
    p.hospital_expire_flag
  FROM 
    patients_of_interest p
  JOIN 
    medication_complexity mc 
      ON p.subject_id = mc.subject_id AND p.hadm_id = mc.hadm_id
),

-- Step 4: Calculate tertiles of medication complexity
medication_tertiles AS (
  SELECT 
    subject_id, 
    hadm_id, 
    medication_complexity_score,
    NTILE(3) OVER (ORDER BY medication_complexity_score) AS tertile,
    admittime,
    dischtime,
    hospital_expire_flag
  FROM 
    patients_with_complexity
),

-- Step 5: Calculate outcomes
outcomes AS (
  SELECT 
    mt.tertile,
    COUNT(DISTINCT mt.hadm_id) AS admission_count,
    MIN(mt.medication_complexity_score) AS min_score,
    MAX(mt.medication_complexity_score) AS max_score,
    AVG(mt.medication_complexity_score) AS mean_score,
    AVG(DATE_DIFF(mt.dischtime, mt.admittime, DAY)) AS mean_LOS,
    SUM(CASE WHEN mt.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT mt.hadm_id) AS in_hospital_mortality_rate
  FROM 
    medication_tertiles mt
  GROUP BY 
    mt.tertile
)

-- Final query
SELECT 
  tertile,
  admission_count,
  CONCAT(STRING(min_score), ' - ', STRING(max_score)) AS score_range,
  mean_score,
  mean_LOS,
  in_hospital_mortality_rate
FROM 
  outcomes
ORDER BY 
  tertile;