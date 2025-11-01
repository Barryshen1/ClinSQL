WITH 
-- Step 1: Identify ACS patients and their primary/secondary diagnosis status
acs_patients AS (
  SELECT di.long_title, d.icd_code, d.subject_id, d.hadm_id, 
         CASE WHEN d.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%Acute coronary syndrome%' OR di.long_title LIKE '%Myocardial infarction%'
),

-- Step 2: Filter patients by age and gender
filtered_patients AS (
  SELECT p.subject_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 59 AND 69
),

-- Step 3: Calculate LOS and count procedures
admission_details AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, 
         DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los,
         COUNT(p.icd_code) AS num_procedures
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id, a.admittime, a.dischtime
),

-- Step 4: Combine the information
combined_data AS (
  SELECT ap.subject_id, ap.hadm_id, ap.diagnosis_type, ad.los, ad.num_procedures
  FROM acs_patients ap
  JOIN admission_details ad ON ap.hadm_id = ad.hadm_id
  JOIN filtered_patients fp ON ap.subject_id = fp.subject_id
),

-- Step 5: Categorize LOS and calculate percentiles
final_data AS (
  SELECT diagnosis_type, 
         CASE WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
              WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
              ELSE 'More than 7 days'
         END AS los_category,
         num_procedures
  FROM combined_data
)

-- Calculate p25, p50, p75 for num_procedures
SELECT diagnosis_type, los_category, 
       APPROX_QUANTILES(num_procedures, 100)[OFFSET(25)] AS p25,
       APPROX_QUANTILES(num_procedures, 100)[OFFSET(50)] AS p50,
       APPROX_QUANTILES(num_procedures, 100)[OFFSET(75)] AS p75
FROM final_data
WHERE los_category IN ('1-3 days', '4-7 days')
GROUP BY diagnosis_type, los_category
ORDER BY diagnosis_type, los_category;