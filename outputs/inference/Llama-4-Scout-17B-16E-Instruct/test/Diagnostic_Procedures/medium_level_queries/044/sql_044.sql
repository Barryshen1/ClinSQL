WITH 
  -- Define lower GI bleed ICD codes
  lower_gi_bleed AS (
    SELECT hadm_id, icd_code
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN ('456.0', '456.1', '456.2', 'K62.1')  -- Example codes for lower GI bleed
  ),
  
  -- Identify non-invasive diagnostics
  non_invasive_diagnostics AS (
    SELECT p.hadm_id, 
           CASE 
             WHEN di.long_title LIKE '%Imaging%' THEN 'Imaging'
             WHEN di.long_title LIKE '%ECG%' THEN 'ECG'
             WHEN di.long_title LIKE '%EEG%' THEN 'EEG'
             WHEN di.long_title LIKE '%PFT%' THEN 'PFT'
             ELSE 'Other'
           END AS diagnostic_type
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` di 
      ON p.icd_code = di.icd_code AND p.icd_version = di.icd_version
  ),
  
  -- Calculate LOS and categorize
  patient_stay AS (
    SELECT a.hadm_id,
           a.admittime,
           a.dischtime,
           TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  ),
  
  -- Determine ICU status
  icu_stay AS (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  )

SELECT 
  CASE 
    WHEN ps.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN ps.los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Outside range'
  END AS los_category,
  COALESCE(icu.hadm_id IS NOT NULL, FALSE) AS in_icu,
  COUNT(nid.hadm_id) AS num_diagnostics
FROM 
  `physionet-data.mimiciv_3_1_hosp.patients` pt
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON pt.subject_id = a.subject_id
  JOIN lower_gi_bleed lgb 
    ON a.hadm_id = lgb.hadm_id
  LEFT JOIN non_invasive_diagnostics nid 
    ON a.hadm_id = nid.hadm_id
  JOIN patient_stay ps 
    ON a.hadm_id = ps.hadm_id
  LEFT JOIN icu_stay icu 
    ON a.hadm_id = icu.hadm_id
WHERE 
  pt.gender = 'F'
  AND pt.anchor_age BETWEEN 62 AND 72
GROUP BY 
  los_category, 
  in_icu;