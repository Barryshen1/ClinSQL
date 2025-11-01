WITH 
-- Step 1: Identify patients with ischemic heart disease
ihd_patients AS (
  SELECT DISTINCT ad.subject_id, ad.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.subject_id = diag.subject_id AND ad.hadm_id = diag.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ad.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
    AND d_diag.long_title LIKE '%Ischemic heart disease%'
),

-- Step 2: Get Troponin-T measurements for these patients
troponin_t_measurements AS (
  SELECT ihp.subject_id, ihp.hadm_id, le.charttime, le.valuenum
  FROM ihd_patients ihp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ihp.subject_id = le.subject_id AND ihp.hadm_id = le.hadm_id
  WHERE le.itemid = 50821  
    AND le.valuenum > 0.014
),

-- Step 3: Get the first Troponin-T measurement for each admission
first_troponin_t AS (
  SELECT subject_id, hadm_id, valuenum,
         ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) as rn
  FROM troponin_t_measurements
)

-- Step 4: Calculate median and IQR
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3
FROM first_troponin_t
WHERE rn = 1;