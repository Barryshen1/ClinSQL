WITH 
-- Step 1: Filter patients by age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 67 AND 77
),

-- Step 2: Identify heart failure admissions and their type (primary/secondary)
heart_failure_admissions AS (
  SELECT 
    a.hadm_id,
    d.icd_code,
    d.icd_version,
    CASE WHEN diag.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS hf_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE diag.icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Heart failure%')
  AND a.subject_id IN (SELECT subject_id FROM eligible_patients)
),

-- Step 3: Calculate LOS and stratify admissions
admission_details AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los,
    CASE 
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATETIME_DIFF(dischtime, admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE 'Outside Range'
    END AS los_category
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE hadm_id IN (SELECT hadm_id FROM heart_failure_admissions)
),

-- Step 4: Count imaging studies per admission (using hcpcsevents as a proxy)
imaging_studies_count AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_imaging_studies
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE hadm_id IN (SELECT hadm_id FROM admission_details)
  GROUP BY hadm_id
)

-- Final query to calculate percentiles
SELECT 
  ad.los_category,
  hfa.hf_type,
  APPROX_QUANTILES(isc.num_imaging_studies, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(isc.num_imaging_studies, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(isc.num_imaging_studies, 100)[OFFSET(75)] AS p75
FROM admission_details ad
JOIN heart_failure_admissions hfa ON ad.hadm_id = hfa.hadm_id
JOIN imaging_studies_count isc ON ad.hadm_id = isc.hadm_id
WHERE ad.los_category != 'Outside Range'
GROUP BY ad.los_category, hfa.hf_type
ORDER BY ad.los_category, hfa.hf_type;