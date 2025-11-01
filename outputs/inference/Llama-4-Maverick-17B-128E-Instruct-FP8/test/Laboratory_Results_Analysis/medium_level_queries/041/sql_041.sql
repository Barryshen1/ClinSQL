WITH 
-- Step 1: Identify hs-Troponin T lab itemid
hs_troponin_t_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE label LIKE '%hs-Troponin T%' OR label LIKE '%Troponin T, high sensitivity%'
),

-- Step 2 & 3: Filter patients and identify ACS admissions
acs_patients AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 43 AND 53
  AND dicd.long_title LIKE '%Acute coronary syndrome%'
),

-- Step 4: Get initial hs-Troponin T values
initial_hs_troponin_t AS (
  SELECT ap.subject_id, ap.hadm_id, l.valuenum, 
         ROW_NUMBER() OVER (PARTITION BY ap.hadm_id ORDER BY l.charttime) as rn,
         l.ref_range_upper
  FROM acs_patients ap
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON ap.hadm_id = l.hadm_id
  INNER JOIN hs_troponin_t_itemid h ON l.itemid = h.itemid
  WHERE l.valuenum IS NOT NULL
),

-- Calculate ULN (Upper Limit of Normal) for hs-Troponin T
uln_hs_troponin_t AS (
  SELECT MAX(ref_range_upper) as uln
  FROM initial_hs_troponin_t
)

-- Step 5: Calculate median and IQR
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS q3
FROM initial_hs_troponin_t
WHERE rn = 1 AND valuenum > (SELECT uln FROM uln_hs_troponin_t);