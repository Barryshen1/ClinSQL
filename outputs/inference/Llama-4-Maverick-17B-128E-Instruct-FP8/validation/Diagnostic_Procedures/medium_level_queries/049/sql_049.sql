WITH 
-- Step 1 & 2: Filter patients and get admissions
eligible_admissions AS (
  SELECT a.hadm_id, p.anchor_age, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 87 AND 97
),

-- Step 3: Simplified identification of sepsis (example ICD codes, actual implementation may vary)
sepsis_admissions AS (
  SELECT ea.hadm_id
  FROM eligible_admissions ea
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON ea.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Sepsis%' OR dicd.long_title LIKE '%septicemia%'
  -- AND exclude septic shock, which would require a similar but specific filter
),

-- Step 4: Calculate admission duration and categorize
admission_durations AS (
  SELECT sa.hadm_id, 
         DATETIME_DIFF(sa.dischtime, sa.admittime, DAY) AS length_of_stay,
         CASE 
           WHEN DATETIME_DIFF(sa.dischtime, sa.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
           WHEN DATETIME_DIFF(sa.dischtime, sa.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
           ELSE NULL
         END AS los_category
  FROM eligible_admissions sa
  JOIN sepsis_admissions ON sa.hadm_id = sepsis_admissions.hadm_id
  WHERE DATETIME_DIFF(sa.dischtime, sa.admittime, DAY) BETWEEN 1 AND 7
),

-- Step 5: Count diagnostic procedures
procedure_counts AS (
  SELECT ad.hadm_id, ad.los_category, COUNT(*) AS num_procedures
  FROM admission_durations ad
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON ad.hadm_id = p.hadm_id
  GROUP BY ad.hadm_id, ad.los_category
)

-- Step 6: Calculate mean diagnostic procedures per LOS category
SELECT los_category, AVG(num_procedures) AS mean_procedures
FROM procedure_counts
GROUP BY los_category;