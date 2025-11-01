WITH 
-- Step 1: Identify the population
patients_cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, p.anchor_age, p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 49 AND 59
),
t2dm_hf_patients AS (
  SELECT DISTINCT pc.subject_id, pc.hadm_id
  FROM patients_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON pc.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE (dicd.long_title LIKE '%Type 2 diabetes%' OR dicd.long_title LIKE '%Heart failure%')
),
icu_stays AS (
  SELECT t2dm_hf.subject_id, t2dm_hf.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM t2dm_hf_patients t2dm_hf
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON t2dm_hf.hadm_id = icu.hadm_id
),

-- Step 2: Determine medication usage
medication_usage AS (
  SELECT icu_stays.subject_id, icu_stays.hadm_id, icu_stays.stay_id, 
         p.starttime, p.drug, 
         CASE 
           WHEN LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%sulfonylurea%' OR LOWER(p.drug) LIKE '%glitazone%' OR LOWER(p.drug) LIKE '%incretin%' OR LOWER(p.drug) LIKE '%insulin%' THEN 'Antidiabetic'
           WHEN LOWER(p.drug) LIKE '%beta blocker%' OR LOWER(p.drug) LIKE '%metoprolol%' OR LOWER(p.drug) LIKE '%propranolol%' OR LOWER(p.drug) LIKE '%atenolol%' THEN 'Beta-Blocker'
           WHEN LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%enalapril%' OR LOWER(p.drug) LIKE '%captopril%' OR LOWER(p.drug) LIKE '%losartan%' OR LOWER(p.drug) LIKE '%valsartan%' THEN 'ACEi/ARB/ARNI'
           WHEN LOWER(p.drug) LIKE '%furosemide%' OR LOWER(p.drug) LIKE '%bumetanide%' OR LOWER(p.drug) LIKE '%torsemide%' THEN 'Loop Diuretic'
           ELSE NULL
         END AS medication_category
  FROM icu_stays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON icu_stays.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN icu_stays.intime AND icu_stays.outtime
),

-- Step 3: Analyze medication usage over time
medication_timing AS (
  SELECT subject_id, hadm_id, stay_id, medication_category,
         CASE 
           WHEN starttime <= intime + INTERVAL 1 DAY THEN 'First 24h'
           ELSE 'Final 48h'
         END AS timing
  FROM (
    SELECT mu.subject_id, mu.hadm_id, mu.stay_id, mu.medication_category, mu.starttime, 
           MIN(icu.intime) OVER (PARTITION BY icu.stay_id) AS intime, 
           MAX(icu.outtime) OVER (PARTITION BY icu.stay_id) AS outtime
    FROM medication_usage mu
    INNER JOIN icu_stays icu ON mu.stay_id = icu.stay_id
  ) sub
  WHERE starttime BETWEEN intime AND outtime
  AND (starttime <= intime + INTERVAL 1 DAY OR starttime >= outtime - INTERVAL 2 DAY)
),

-- Step 4: Categorize medication status
medication_status AS (
  SELECT subject_id, hadm_id, stay_id, medication_category,
         COUNT(CASE WHEN timing = 'First 24h' THEN 1 END) AS count_first_24h,
         COUNT(CASE WHEN timing = 'Final 48h' THEN 1 END) AS count_final_48h
  FROM medication_timing
  GROUP BY subject_id, hadm_id, stay_id, medication_category
)

-- Final output
SELECT medication_category,
       COUNT(CASE WHEN count_first_24h > 0 THEN 1 END) AS num_patients_first_24h,
       COUNT(CASE WHEN count_final_48h > 0 THEN 1 END) AS num_patients_final_48h,
       COUNT(CASE WHEN count_first_24h > 0 AND count_final_48h > 0 THEN 1 END) AS continued,
       COUNT(CASE WHEN count_first_24h = 0 AND count_final_48h > 0 THEN 1 END) AS initiated,
       COUNT(CASE WHEN count_first_24h > 0 AND count_final_48h = 0 THEN 1 END) AS discontinued
FROM medication_status
GROUP BY medication_category;