WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT subject_id, anchor_age, gender, dod
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 44 AND 54
  ),
  
  -- Admissions with TIA
  tia_admissions AS (
    SELECT a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN patients_of_interest p ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
    WHERE d.icd_code LIKE '435%'  -- TIA ICD code
  ),
  
  -- ICU stays
  icu_stays AS (
    SELECT hadm_id, stay_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ),
  
  -- Diagnostic imaging events (example: procedures)
  diagnostic_imaging AS (
    SELECT hadm_id, COUNT(*) as imaging_count
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY hadm_id
  ),
  
  -- LOS calculation
  admissions_with_los AS (
    SELECT hadm_id, 
           TIMESTAMP_DIFF(dischtime, admittime, DAY) as los
    FROM tia_admissions
  ),
  
  -- Combine all information
  combined_data AS (
    SELECT 
      a.hadm_id,
      CASE 
        WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
        WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7'
        ELSE 'Outside range'
      END as los_category,
      IFNULL(i.stay_id, 0) as icu_use,
      d.imaging_count
    FROM tia_admissions a
    LEFT JOIN icu_stays i ON a.hadm_id = i.hadm_id
    LEFT JOIN diagnostic_imaging d ON a.hadm_id = d.hadm_id
  )

-- Calculate percentiles
SELECT 
  los_category,
  icu_use,
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY imaging_count) AS p25,
  PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY imaging_count) AS p50,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY imaging_count) AS p75
FROM combined_data
WHERE imaging_count IS NOT NULL
GROUP BY los_category, icu_use;