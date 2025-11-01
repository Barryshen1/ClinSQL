WITH 
-- Step 1: Filter patients
filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 49 AND 59
),

-- Step 2: Identify heart failure admissions
heart_failure_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE di.seq_num = 1 AND dicd.long_title LIKE '%Heart failure%'
  AND a.subject_id IN (SELECT subject_id FROM filtered_patients)
),

-- Step 3: Calculate LOS and determine ICU use
admission_details AS (
  SELECT hadm_id, 
         DATETIME_DIFF(dischtime, admittime, DAY) AS los,
         EXISTS (SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` WHERE hadm_id = hf.hadm_id) AS icu_use
  FROM heart_failure_admissions hf
),

-- Step 4: Count CT/MRI procedures
ct_mri_counts AS (
  SELECT h.hadm_id, COUNT(*) AS ct_mri_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` dh ON h.hcpcs_cd = dh.code
  WHERE dh.short_description LIKE '%CT%' OR dh.short_description LIKE '%MRI%'
  GROUP BY h.hadm_id
)

-- Final aggregation
SELECT 
  CASE 
    WHEN ad.los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN ad.los BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'outside range'
  END AS los_category,
  ad.icu_use,
  COUNT(ad.hadm_id) AS admission_count,
  AVG(IFNULL(cm.ct_mri_count, 0)) AS mean_ct_mri
FROM admission_details ad
LEFT JOIN ct_mri_counts cm ON ad.hadm_id = cm.hadm_id
WHERE ad.los BETWEEN 1 AND 7
GROUP BY los_category, ad.icu_use
ORDER BY los_category, ad.icu_use;