WITH cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 81 AND 91
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10 AND icd_code LIKE 'E11%'
  )
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 10 AND icd_code LIKE 'I50%'
  )
),
medications AS (
  SELECT c.hadm_id, 
         CASE 
           WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
           WHEN LOWER(p.drug) LIKE '%sulfonylurea%' OR LOWER(p.drug) LIKE '%glimepiride%' OR LOWER(p.drug) LIKE '%glyburide%' THEN 'Sulfonylurea'
           WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP4'
           WHEN LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2'
           WHEN LOWER(p.drug) LIKE '%pioglitazone%' THEN 'TZD'
           ELSE NULL
         END AS medication_class,
         p.starttime, c.admittime, c.dischtime
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN c.admittime AND c.dischtime
  AND (
    LOWER(p.drug) LIKE '%metformin%' 
    OR LOWER(p.drug) LIKE '%sulfonylurea%' OR LOWER(p.drug) LIKE '%glimepiride%' OR LOWER(p.drug) LIKE '%glyburide%'
    OR LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%'
    OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%'
    OR LOWER(p.drug) LIKE '%pioglitazone%'
  )
),
medication_period AS (
  SELECT hadm_id, medication_class,
         COUNT(DISTINCT CASE WHEN starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) THEN medication_class END) AS count_first_72h,
         COUNT(DISTINCT CASE WHEN starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN medication_class END) AS count_last_48h
  FROM medications
  GROUP BY hadm_id, medication_class
),
prevalence AS (
  SELECT medication_class,
         COUNT(CASE WHEN count_first_72h > 0 THEN 1 END) / COUNT(*) * 100 AS prevalence_first_72h,
         COUNT(CASE WHEN count_last_48h > 0 THEN 1 END) / COUNT(*) * 100 AS prevalence_last_48h
  FROM medication_period
  GROUP BY medication_class
)
SELECT medication_class,
       prevalence_first_72h,
       prevalence_last_48h,
       prevalence_last_48h - prevalence_first_72h AS abs_pp_diff
FROM prevalence
ORDER BY medication_class;