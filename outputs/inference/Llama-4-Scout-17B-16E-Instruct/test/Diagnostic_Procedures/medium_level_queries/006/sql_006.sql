WITH 
  -- Define age range and gender
  target_patients AS (
    SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
    WHERE p.gender = 'M' AND p.anchor_age BETWEEN 48 AND 58
  ),

  -- Identify sepsis cases (simplified, might need refinement based on ICD codes)
  sepsis_patients AS (
    SELECT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE ' sepsis%'  -- This might need adjustment based on actual ICD codes in MIMIC-IV
  ),

  -- Determine ICU stays
  icu_stays AS (
    SELECT subject_id, hadm_id, stay_id, intime, outtime
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ),

  -- Identify ultrasounds
  ultrasounds AS (
    SELECT hadm_id, COUNT(*) AS ultrasound_count
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` ON labevents.itemid = d_labitems.itemid
    WHERE d_labitems.label LIKE '%Ultrasound%'  -- Adjust based on actual lab item labels
    GROUP BY hadm_id
  ),

  -- Combine information
  patient_data AS (
    SELECT tp.hadm_id, 
           tp.subject_id,
           CASE 
             WHEN icu.hadm_id IS NOT NULL THEN 'ICU'
             ELSE 'No ICU'
           END AS icu_status,
           CASE 
             WHEN DATE_DIFF(tp.dischtime, tp.admittime, 'DAY') BETWEEN 1 AND 4 THEN '1-4 days'
             WHEN DATE_DIFF(tp.dischtime, tp.admittime, 'DAY') BETWEEN 5 AND 8 THEN '5-8 days'
             ELSE 'Outside range'
           END AS los_category,
           COALESCE(u.ultrasound_count, 0) AS ultrasound_count
    FROM target_patients tp
    LEFT JOIN sepsis_patients sp ON tp.hadm_id = sp.hadm_id
    LEFT JOIN icu_stays icu ON tp.hadm_id = icu.hadm_id
    LEFT JOIN ultrasounds u ON tp.hadm_id = u.hadm_id
    WHERE tp.subject_id IN (SELECT subject_id FROM sepsis_patients)
  )

-- Final aggregation
SELECT icu_status, los_category, COUNT(DISTINCT hadm_id) AS patient_count, 
       AVG(ultrasound_count) AS mean_ultrasound_admission
FROM patient_data
WHERE los_category != 'Outside range'
GROUP BY icu_status, los_category
ORDER BY icu_status, los_category;