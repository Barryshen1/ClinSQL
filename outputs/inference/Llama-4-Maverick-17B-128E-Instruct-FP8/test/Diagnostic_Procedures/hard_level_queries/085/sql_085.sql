WITH 
-- Step 1: Filter patients by age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 87 AND 97
),

-- Step 2: Identify patients with lower GI bleeding
gi_bleed_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%Gastrointestinal hemorrhage%' 
    OR diag.long_title LIKE '%Lower gastrointestinal bleed%'
),

-- Step 3: First ICU stay for eligible patients
first_icu_stay AS (
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime, i.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN (
    SELECT subject_id, hadm_id, MIN(intime) AS first_intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    GROUP BY subject_id, hadm_id
  ) first_icu ON i.subject_id = first_icu.subject_id AND i.hadm_id = first_icu.hadm_id AND i.intime = first_icu.first_intime
),

-- Step 4: Count distinct procedures in the first 48 hours
procedure_counts AS (
  SELECT f.stay_id, COUNT(DISTINCT p.itemid) AS num_procedures
  FROM first_icu_stay f
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` p
    ON f.stay_id = p.stay_id AND p.starttime BETWEEN f.intime AND TIMESTAMP_ADD(f.intime, INTERVAL 48 HOUR)
  GROUP BY f.stay_id
),

-- Step 5: Calculate ICU LOS and in-hospital mortality
patient_outcomes AS (
  SELECT f.stay_id, f.los, a.hospital_expire_flag
  FROM first_icu_stay f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON f.hadm_id = a.hadm_id
),

-- Step 6: Combine data and stratify by quintiles of distinct procedures
quintile_analysis AS (
  SELECT 
    p.num_procedures,
    o.los,
    o.hospital_expire_flag,
    NTILE(5) OVER (ORDER BY p.num_procedures) AS quintile
  FROM procedure_counts p
  JOIN patient_outcomes o ON p.stay_id = o.stay_id
),

-- Step 7: Calculate statistics for each quintile
final_stats AS (
  SELECT 
    quintile,
    AVG(num_procedures) AS mean_procedure_count,
    AVG(los) AS mean_icu_los,
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct
  FROM quintile_analysis
  GROUP BY quintile
)

SELECT * FROM final_stats
ORDER BY quintile;