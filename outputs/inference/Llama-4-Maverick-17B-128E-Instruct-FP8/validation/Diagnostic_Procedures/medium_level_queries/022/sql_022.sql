WITH 
-- Step 1: Filter patients based on age and gender
cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age = 74
),

-- Step 2: Identify heart failure patients
heart_failure AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Heart failure%'
),

-- Step 3: Admission details
admissions_details AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cohort ON a.subject_id = cohort.subject_id
  JOIN heart_failure ON a.hadm_id = heart_failure.hadm_id
),

-- Step 4: Non-invasive diagnostics count
diagnostics_count AS (
  SELECT 
    hadm_id, 
    COUNT(CASE WHEN type = 'imaging' THEN 1 END) AS imaging_count,
    COUNT(CASE WHEN type = 'ecg_eeg' THEN 1 END) AS ecg_eeg_count,
    COUNT(CASE WHEN type = 'pft' THEN 1 END) AS pft_count
  FROM (
    -- Imaging (using hcpcsevents as a proxy)
    SELECT hadm_id, 'imaging' AS type
    FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
    WHERE hadm_id IN (SELECT hadm_id FROM admissions_details)

    UNION ALL

    -- ECG/EEG (using chartevents in ICU as a proxy)
    SELECT hadm_id, 'ecg_eeg'
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label LIKE '%ECG%' OR label LIKE '%EEG%')
    AND hadm_id IN (SELECT hadm_id FROM admissions_details)

    UNION ALL

    -- PFT (assuming it's in labevents, adjust as necessary)
    SELECT hadm_id, 'pft'
    FROM `physionet-data.mimiciv_3_1_hosp.labevents`
    WHERE itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE label LIKE '%PFT%')
    AND hadm_id IN (SELECT hadm_id FROM admissions_details)
  )
  GROUP BY hadm_id
)

-- Final query
SELECT 
  admission_type,
  CASE 
    WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN los BETWEEN 5 AND 7 THEN '5-7 days'
  END AS los_category,
  AVG(imaging_count) AS mean_imaging,
  AVG(ecg_eeg_count) AS mean_ecg_eeg,
  AVG(pft_count) AS mean_pft
FROM admissions_details
JOIN diagnostics_count ON admissions_details.hadm_id = diagnostics_count.hadm_id
WHERE los BETWEEN 1 AND 7
GROUP BY admission_type, los_category
ORDER BY admission_type, los_category;