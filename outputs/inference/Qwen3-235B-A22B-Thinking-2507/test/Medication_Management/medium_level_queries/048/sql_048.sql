WITH 
-- Calculate age at admission
patients_with_age AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 65 AND 75
),

-- Identify patients with diabetes
diabetes_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '250%')
     OR (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR 
                              icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR 
                              icd_code LIKE 'E12%' OR icd_code LIKE 'E13%'))
),

-- Identify patients with heart failure
heart_failure_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 9 AND icd_code LIKE '428%')
     OR (icd_version = 10 AND icd_code LIKE 'I50%')
),

-- Combine to get target population with stay duration >= 96 hours
target_population AS (
  SELECT
    pwa.subject_id,
    pwa.hadm_id,
    pwa.admittime,
    pwa.dischtime
  FROM patients_with_age pwa
  INNER JOIN diabetes_patients dp ON pwa.hadm_id = dp.hadm_id
  INNER JOIN heart_failure_patients hfp ON pwa.hadm_id = hfp.hadm_id
  WHERE TIMESTAMP_DIFF(pwa.dischtime, pwa.admittime, HOUR) >= 96
),

-- Identify insulin prescriptions and categorize them
insulin_orders AS (
  SELECT
    po.hadm_id,
    po.starttime,
    po.stoptime,
    -- Basal insulin: long-acting
    CASE 
      WHEN LOWER(po.drug) LIKE '%glargine%' OR 
           LOWER(po.drug) LIKE '%detemir%' OR 
           LOWER(po.drug) LIKE '%degludec%' 
      THEN 1 ELSE 0 
    END AS is_basal,
    -- Bolus insulin: short-acting
    CASE 
      WHEN LOWER(po.drug) LIKE '%aspart%' OR 
           LOWER(po.drug) LIKE '%lispro%' OR 
           LOWER(po.drug) LIKE '%regular%' 
      THEN 1 ELSE 0 
    END AS is_bolus,
    -- Sliding scale insulin
    CASE 
      WHEN LOWER(po.drug) LIKE '%sliding scale%' OR 
           LOWER(po.drug) LIKE '%correction%' OR 
           LOWER(po.drug) LIKE '%sliding-scale%' 
      THEN 1 ELSE 0 
    END AS is_sliding_scale
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` po
  WHERE 
    -- Look for any insulin-related drugs
    LOWER(po.drug) LIKE '%insulin%'
),

-- Define time windows for each patient
time_windows AS (
  SELECT
    tp.hadm_id,
    tp.admittime,
    tp.dischtime,
    tp.admittime AS first_48h_start,
    TIMESTAMP_ADD(tp.admittime, INTERVAL 48 HOUR) AS first_48h_end,
    TIMESTAMP_SUB(tp.dischtime, INTERVAL 48 HOUR) AS final_48h_start,
    tp.dischtime AS final_48h_end
  FROM target_population tp
),

-- Determine regimen presence in each time window
regimen_flags AS (
  SELECT
    tw.hadm_id,
    -- First 48 hours
    MAX(CASE 
          WHEN io.starttime < tw.first_48h_end AND io.stoptime > tw.first_48h_start 
          THEN io.is_basal ELSE 0 
        END) AS first_basal,
    MAX(CASE 
          WHEN io.starttime < tw.first_48h_end AND io.stoptime > tw.first_48h_start 
          THEN io.is_bolus ELSE 0 
        END) AS first_bolus,
    MAX(CASE 
          WHEN io.starttime < tw.first_48h_end AND io.stoptime > tw.first_48h_start 
          THEN io.is_sliding_scale ELSE 0 
        END) AS first_sliding_scale,
    -- Final 48 hours
    MAX(CASE 
          WHEN io.starttime < tw.final_48h_end AND io.stoptime > tw.final_48h_start 
          THEN io.is_basal ELSE 0 
        END) AS final_basal,
    MAX(CASE 
          WHEN io.starttime < tw.final_48h_end AND io.stoptime > tw.final_48h_start 
          THEN io.is_bolus ELSE 0 
        END) AS final_bolus,
    MAX(CASE 
          WHEN io.starttime < tw.final_48h_end AND io.stoptime > tw.final_48h_start 
          THEN io.is_sliding_scale ELSE 0 
        END) AS final_sliding_scale
  FROM time_windows tw
  LEFT JOIN insulin_orders io ON tw.hadm_id = io.hadm_id
  GROUP BY tw.hadm_id
),

-- Calculate basal-bolus as combination of basal and bolus
patient_regimens AS (
  SELECT
    hadm_id,
    first_basal,
    first_bolus,
    first_basal * first_bolus AS first_basal_bolus,
    first_sliding_scale,
    final_basal,
    final_bolus,
    final_basal * final_bolus AS final_basal_bolus,
    final_sliding_scale
  FROM regimen_flags
),

-- Aggregate results
regimen_counts AS (
  SELECT
    'basal' AS regimen_type,
    SUM(first_basal) AS first_count,
    SUM(final_basal) AS final_count,
    COUNT(*) AS total_patients
  FROM patient_regimens
  
  UNION ALL
  
  SELECT
    'bolus' AS regimen_type,
    SUM(first_bolus) AS first_count,
    SUM(final_bolus) AS final_count,
    COUNT(*) AS total_patients
  FROM patient_regimens
  
  UNION ALL
  
  SELECT
    'basal-bolus' AS regimen_type,
    SUM(first_basal_bolus) AS first_count,
    SUM(final_basal_bolus) AS final_count,
    COUNT(*) AS total_patients
  FROM patient_regimens
  
  UNION ALL
  
  SELECT
    'sliding-scale' AS regimen_type,
    SUM(first_sliding_scale) AS first_count,
    SUM(final_sliding_scale) AS final_count,
    COUNT(*) AS total_patients
  FROM patient_regimens
)

-- Final result with percentages
SELECT
  regimen_type,
  ROUND((first_count / total_patients) * 100, 2) AS first_48h_pct,
  ROUND((final_count / total_patients) * 100, 2) AS final_48h_pct
FROM regimen_counts;