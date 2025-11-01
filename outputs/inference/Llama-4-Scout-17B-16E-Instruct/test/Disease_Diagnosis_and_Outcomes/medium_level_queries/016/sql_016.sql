WITH 
-- Identify AMI patients without shock or respiratory failure
ami_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    ic.stay_id,
    ic.intime AS icu_intime,
    ic.outtime AS icu_outtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic ON a.hadm_id = ic.hadm_id
  WHERE 
    dd.long_title LIKE '%Acute myocardial infarction%' 
    AND a.admission_type NOT IN ('trauma', 'elective')
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),

-- Calculate hospital mortality and LOS
patient_outcomes AS (
  SELECT 
    ap.subject_id,
    ap.hadm_id,
    ap.admittime,
    ap.dischtime,
    ap.deathtime,
    CASE 
      WHEN ap.deathtime IS NOT NULL THEN 1 
      ELSE 0 
    END AS in_hospital_mortality,
    DATE_DIFF(ap.dischtime, ap.admittime) AS los,
    CASE 
      WHEN ic.intime IS NOT NULL AND DATE_DIFF(ic.intime, ap.admittime) = 0 THEN 'Yes'
      ELSE 'No'
    END AS day_1_icu
  FROM 
    ami_patients ap
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic ON ap.hadm_id = ic.hadm_id
)

-- Final analysis
SELECT 
  los_group,
  day_1_icu,
  COUNT(DISTINCT hadm_id) AS total_patients,
  SUM(in_hospital_mortality) AS total_mortality,
  SAFE_DIVIDE(SUM(in_hospital_mortality), COUNT(DISTINCT hadm_id)) AS mortality_rate,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY los) OVER (PARTITION BY los_group, day_1_icu) AS median_los
FROM (
  SELECT 
    hadm_id,
    in_hospital_mortality,
    los,
    day_1_icu,
    CASE 
      WHEN los <= 5 THEN 'LOS_<=5'
      ELSE 'LOS_>5'
    END AS los_group
  FROM 
    patient_outcomes
)
GROUP BY 
  los_group, day_1_icu
ORDER BY 
  los_group, day_1_icu;