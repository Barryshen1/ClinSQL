WITH 
diabetes_codes AS (
  SELECT hadm_id, subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%') OR
    (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E10','E11','E12','E13','E14'))
),
acute_hf_codes AS (
  SELECT hadm_id, subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('42821','42823','42841','42843')) OR
    (icd_version = 10 AND icd_code IN ('I50.21','I50.23','I50.31','I50.33','I50.41','I50.43'))
),
cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.anchor_age BETWEEN 71 AND 81
    AND EXISTS (
      SELECT 1 FROM diabetes_codes dc 
      WHERE dc.subject_id = adm.subject_id AND dc.hadm_id = adm.hadm_id
    )
    AND EXISTS (
      SELECT 1 FROM acute_hf_codes hf 
      WHERE hf.subject_id = adm.subject_id AND hf.hadm_id = adm.hadm_id
    )
),
cohort_meds AS (
  SELECT 
    cohort.hadm_id,
    -- Metformin flags
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%metformin%' 
          AND p.starttime BETWEEN cohort.admittime 
            AND LEAST(DATETIME_ADD(cohort.admittime, INTERVAL 72 HOUR), cohort.dischtime)
          THEN 1 ELSE 0 
        END) AS metformin_first72h,
    MAX(CASE 
          WHEN LOWER(p.drug) LIKE '%metformin%' 
          AND p.starttime BETWEEN 
            GREATEST(cohort.admittime, DATETIME_SUB(cohort.dischtime, INTERVAL 48 HOUR)) 
            AND cohort.dischtime
          THEN 1 ELSE 0 
        END) AS metformin_last48h,
    -- Sulfonylureas flags
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%glipi%' OR 
                LOWER(p.drug) LIKE '%glyburide%' OR 
                LOWER(p.drug) LIKE '%gliclazide%' OR 
                LOWER(p.drug) LIKE '%tolbutamide%' OR 
                LOWER(p.drug) LIKE '%chlorpropamide%' OR 
                LOWER(p.drug) LIKE '%tolazamide%' OR 
                LOWER(p.drug) LIKE '%acetohexamide%')
          AND p.starttime BETWEEN cohort.admittime 
            AND LEAST(DATETIME_ADD(cohort.admittime, INTERVAL 72 HOUR), cohort.dischtime)
          THEN 1 ELSE 0 
        END) AS sulfonylureas_first72h,
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%glipi%' OR 
                LOWER(p.drug) LIKE '%glyburide%' OR 
                LOWER(p.drug) LIKE '%gliclazide%' OR 
                LOWER(p.drug) LIKE '%tolbutamide%' OR 
                LOWER(p.drug) LIKE '%chlorpropamide%' OR 
                LOWER(p.drug) LIKE '%tolazamide%' OR 
                LOWER(p.drug) LIKE '%acetohexamide%')
          AND p.starttime BETWEEN 
            GREATEST(cohort.admittime, DATETIME_SUB(cohort.dischtime, INTERVAL 48 HOUR)) 
            AND cohort.dischtime
          THEN 1 ELSE 0 
        END) AS sulfonylureas_last48h,
    -- DPP-4 flags
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%sitagliptin%' OR 
                LOWER(p.drug) LIKE '%saxagliptin%' OR 
                LOWER(p.drug) LIKE '%linagliptin%' OR 
                LOWER(p.drug) LIKE '%alogliptin%')
          AND p.starttime BETWEEN cohort.admittime 
            AND LEAST(DATETIME_ADD(cohort.admittime, INTERVAL 72 HOUR), cohort.dischtime)
          THEN 1 ELSE 0 
        END) AS dpp4_first72h,
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%sitagliptin%' OR 
                LOWER(p.drug) LIKE '%saxagliptin%' OR 
                LOWER(p.drug) LIKE '%linagliptin%' OR 
                LOWER(p.drug) LIKE '%alogliptin%')
          AND p.starttime BETWEEN 
            GREATEST(cohort.admittime, DATETIME_SUB(cohort.dischtime, INTERVAL 48 HOUR)) 
            AND cohort.dischtime
          THEN 1 ELSE 0 
        END) AS dpp4_last48h,
    -- SGLT2 flags
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%canagliflozin%' OR 
                LOWER(p.drug) LIKE '%dapagliflozin%' OR 
                LOWER(p.drug) LIKE '%empagliflozin%' OR 
                LOWER(p.drug) LIKE '%ertugliflozin%')
          AND p.starttime BETWEEN cohort.admittime 
            AND LEAST(DATETIME_ADD(cohort.admittime, INTERVAL 72 HOUR), cohort.dischtime)
          THEN 1 ELSE 0 
        END) AS sglt2_first72h,
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%canagliflozin%' OR 
                LOWER(p.drug) LIKE '%dapagliflozin%' OR 
                LOWER(p.drug) LIKE '%empagliflozin%' OR 
                LOWER(p.drug) LIKE '%ertugliflozin%')
          AND p.starttime BETWEEN 
            GREATEST(cohort.admittime, DATETIME_SUB(cohort.dischtime, INTERVAL 48 HOUR)) 
            AND cohort.dischtime
          THEN 1 ELSE 0 
        END) AS sglt2_last48h,
    -- Thiazolidinediones flags
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%pioglitazone%' OR 
                LOWER(p.drug) LIKE '%rosiglitazone%')
          AND p.starttime BETWEEN cohort.admittime 
            AND LEAST(DATETIME_ADD(cohort.admittime, INTERVAL 72 HOUR), cohort.dischtime)
          THEN 1 ELSE 0 
        END) AS tzd_first72h,
    MAX(CASE 
          WHEN (LOWER(p.drug) LIKE '%pioglitazone%' OR 
                LOWER(p.drug) LIKE '%rosiglitazone%')
          AND p.starttime BETWEEN 
            GREATEST(cohort.admittime, DATETIME_SUB(cohort.dischtime, INTERVAL 48 HOUR)) 
            AND cohort.dischtime
          THEN 1 ELSE 0 
        END) AS tzd_last48h
  FROM cohort
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON cohort.hadm_id = p.hadm_id
  GROUP BY cohort.hadm_id
)
SELECT 
  COUNT(*) AS total_admissions,
  AVG(metformin_first72h) * 100 AS metformin_first72h_rate,
  AVG(metformin_last48h) * 100 AS metformin_last48h_rate,
  AVG(sulfonylureas_first72h) * 100 AS sulfonylureas_first72h_rate,
  AVG(sulfonylureas_last48h) * 100 AS sulfonylureas_last48h_rate,
  AVG(dpp4_first72h) * 100 AS dpp4_first72h_rate,
  AVG(dpp4_last48h) * 100 AS dpp4_last48h_rate,
  AVG(sglt2_first72h) * 100 AS sglt2_first72h_rate,
  AVG(sglt2_last48h) * 100 AS sglt2_last48h_rate,
  AVG(tzd_first72h) * 100 AS tzd_first72h_rate,
  AVG(tzd_last48h) * 100 AS tzd_last48h_rate
FROM cohort_meds;