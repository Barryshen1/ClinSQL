WITH patients_71_81 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 71 AND 81
),
lgib_admissions AS (
  SELECT a.hadm_id, 
         MIN(CASE WHEN d.icd_code IS NOT NULL THEN 1 ELSE 0 END) AS has_lgib_diagnosis,
         MIN(CASE WHEN d.seq_num = 1 THEN 1 ELSE 0 END) AS lgib_primary_diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE a.subject_id IN (SELECT subject_id FROM patients_71_81)
  AND d.icd_code LIKE 'K92.1%'  -- ICD-10 code for GI bleed; adjust as needed for ICD-9
  GROUP BY a.hadm_id
),
admission_los AS (
  SELECT hadm_id, 
         DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
radiography_ct AS (
  SELECT hadm_id, COUNT(*) AS num_radiography_ct
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE hcpcs_cd IN ('74210', '74160', '74170', '72193', '72194', '72195')  -- Example codes for radiography/CT; adjust as needed
  GROUP BY hadm_id
)
SELECT 
  CASE 
    WHEN a.los BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN a.los BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'outside range'
  END AS los_category,
  CASE WHEN l.lgib_primary_diagnosis = 1 THEN 'Primary diagnosis' ELSE 'Secondary diagnosis' END AS diagnosis_category,
  AVG(r.num_radiography_ct) AS mean_radiography_ct
FROM lgib_admissions l
JOIN admission_los a ON l.hadm_id = a.hadm_id
LEFT JOIN radiography_ct r ON l.hadm_id = r.hadm_id
WHERE l.has_lgib_diagnosis = 1 AND a.los BETWEEN 1 AND 7
GROUP BY los_category, diagnosis_category
ORDER BY los_category, diagnosis_category;