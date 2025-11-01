WITH 
-- Filter patients by age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 83 AND 93
),

-- Identify ACS admissions and diagnosis type
acs_admissions AS (
  SELECT a.hadm_id, 
         a.subject_id,
         CASE WHEN d.seq_num = (SELECT MIN(seq_num) FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 WHERE d2.hadm_id = d.hadm_id) THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON d.hadm_id = a.hadm_id
  WHERE (dicd.long_title LIKE '%Acute Coronary Syndrome%' OR dicd.long_title LIKE '%Myocardial Infarction%') 
  AND a.subject_id IN (SELECT subject_id FROM eligible_patients)
),

-- Calculate length of stay
los AS (
  SELECT hadm_id, 
         DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) + 1 AS length_of_stay
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Count ultrasounds
ultrasounds AS (
  SELECT hadm_id, COUNT(*) AS num_ultrasounds
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` p
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON p.itemid = di.itemid
  WHERE di.label LIKE '%Ultrasound%' OR di.label LIKE '%Echo%'
  GROUP BY hadm_id
)

-- Main query
SELECT 
  diagnosis_type,
  CASE WHEN l.length_of_stay BETWEEN 1 AND 4 THEN '1-4 days'
       WHEN l.length_of_stay BETWEEN 5 AND 7 THEN '5-7 days'
       ELSE 'Other'
  END AS los_category,
  COUNT(*) AS num_admissions,
  AVG(u.num_ultrasounds) AS mean_ultrasounds,
  MIN(u.num_ultrasounds) AS min_ultrasounds,
  MAX(u.num_ultrasounds) AS max_ultrasounds
FROM acs_admissions aa
JOIN los l ON aa.hadm_id = l.hadm_id
LEFT JOIN ultrasounds u ON aa.hadm_id = u.hadm_id
WHERE l.length_of_stay BETWEEN 1 AND 7
GROUP BY diagnosis_type, los_category
ORDER BY diagnosis_type, los_category;