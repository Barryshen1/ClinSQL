WITH 
-- Step 1 & 2: Identify female patients aged 38-48 with AKI
aki_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag_desc ON diag.icd_code = diag_desc.icd_code AND diag.icd_version = diag_desc.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND diag_desc.long_title LIKE '%Acute kidney injury%'  -- Simplification for AKI
),

-- Step 3: Calculate hospital LOS and ICU use
admission_details AS (
  SELECT a.hadm_id,
         DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los,
         EXISTS(SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` icu WHERE icu.hadm_id = a.hadm_id) AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE a.hadm_id IN (SELECT hadm_id FROM aki_admissions)
),

-- Step 4: Count non-invasive diagnostics (using labevents as a proxy)
lab_counts AS (
  SELECT hadm_id, COUNT(*) AS num_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE hadm_id IN (SELECT hadm_id FROM aki_admissions)
  GROUP BY hadm_id
)

-- Step 5: Stratify and aggregate
SELECT 
  ad.icu_use,
  CASE 
    WHEN ad.hospital_los BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN ad.hospital_los BETWEEN 5 AND 7 THEN '5-7 days'
    ELSE 'Outside range'
  END AS los_category,
  COUNT(ad.hadm_id) AS num_admissions,
  AVG(lc.num_labs) AS mean_labs,
  MIN(lc.num_labs) AS min_labs,
  MAX(lc.num_labs) AS max_labs
FROM admission_details ad
INNER JOIN lab_counts lc ON ad.hadm_id = lc.hadm_id
WHERE ad.hospital_los BETWEEN 1 AND 7
GROUP BY ad.icu_use, los_category
ORDER BY ad.icu_use, los_category;