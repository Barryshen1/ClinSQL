WITH 
-- Step 1: Identify patients with septic shock
septic_shock_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  WHERE diag.long_title LIKE '%Septic shock%' AND d.icd_version = 10
),

-- Step 2: Filter patients based on age, gender, and presence in septic_shock_patients
filtered_patients AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, 
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
         CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'No ICU' END AS icu_status
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 57 AND 67
    AND a.hadm_id IN (SELECT hadm_id FROM septic_shock_patients)
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Step 3: Count ultrasounds per admission
ultrasound_counts AS (
  SELECT h.hadm_id, COUNT(*) AS ultrasound_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE d.short_description LIKE '%Ultrasound%' OR d.short_description LIKE '%Echocardiogram%'
  GROUP BY h.hadm_id
),

-- Step 4: Combine filtered patients with ultrasound counts and stratify
combined_data AS (
  SELECT fp.hadm_id, fp.los, fp.icu_status, COALESCE(uc.ultrasound_count, 0) AS ultrasound_count,
         CASE WHEN fp.los BETWEEN 1 AND 3 THEN '1-3 days'
              WHEN fp.los BETWEEN 4 AND 7 THEN '4-7 days' END AS los_group
  FROM filtered_patients fp
  LEFT JOIN ultrasound_counts uc
    ON fp.hadm_id = uc.hadm_id
  WHERE fp.los BETWEEN 1 AND 7
)

-- Step 5: Calculate percentiles
SELECT los_group, icu_status,
       APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(25)] AS p25,
       APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(50)] AS p50,
       APPROX_QUANTILES(ultrasound_count, 100)[OFFSET(75)] AS p75
FROM combined_data
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;