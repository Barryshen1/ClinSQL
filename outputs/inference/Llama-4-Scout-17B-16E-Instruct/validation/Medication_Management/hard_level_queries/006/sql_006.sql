WITH 
-- Filter patients of interest
patients_of_interest AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    a.admission_type,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type = 'postoperative'
),

-- Identify ICU stays for these patients
icu_stays AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    outtime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE 
    hadm_id IN (SELECT hadm_id FROM patients_of_interest)
),

-- Calculate medication complexity in the first 72 hours of ICU stay
medication_complexity AS (
  SELECT 
    i.hadm_id,
    COUNT(DISTINCT p.medication) AS num_medications
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.pharmacy` p
  ON 
    i.hadm_id = p.hadm_id
  WHERE 
    p.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 3 DAY)
  GROUP BY 
    i.hadm_id
),

-- Combine data for analysis
combined_data AS (
  SELECT 
    poi.subject_id,
    poi.hadm_id,
    poi.admittime,
    poi.dischtime,
    poi.hospital_expire_flag,
    COALESCE(mc.num_medications, 0) AS num_medications,
    icu.intime AS icu_intime,
    icu.outtime AS icu_outtime
  FROM 
    patients_of_interest poi
  LEFT JOIN 
    icu_stays icu
  ON 
    poi.hadm_id = icu.hadm_id
  LEFT JOIN 
    medication_complexity mc
  ON 
    poi.hadm_id = mc.hadm_id
),

-- Calculate LOS, in-hospital mortality, and 30-day readmission
outcomes AS (
  SELECT 
    subject_id,
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los,
    hospital_expire_flag,
    -- Simplified 30-day readmission flag, actual implementation requires more complex logic
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = subject_id 
          AND a2.admittime BETWEEN TIMESTAMP_ADD(dischtime, INTERVAL 1 DAY) AND TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY)
      ) THEN 1 
      ELSE 0 
    END AS readmitted
  FROM 
    combined_data
),

-- Stratify into quintiles based on medication complexity
quintiles AS (
  SELECT 
    subject_id,
    hadm_id,
    num_medications,
    los,
    hospital_expire_flag,
    readmitted,
    NTILE(5) OVER (ORDER BY num_medications) AS quintile
  FROM 
    outcomes
)

-- Final query
SELECT 
  quintile,
  AVG(num_medications) AS avg_medication_complexity,
  AVG(los) AS avg_los,
  SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_rate,
  AVG(readmitted) AS thirty_day_readmission_rate
FROM 
  quintiles
GROUP BY 
  quintile
ORDER BY 
  quintile;