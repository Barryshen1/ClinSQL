WITH cohort_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 71 AND 81
    -- require discharge (inpatient)
    AND a.dischtime IS NOT NULL
    -- Diabetes mellitus present for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
              dd.long_title LIKE '%Diabetes mellitus%'
              OR di.icd_code LIKE '250%'
             )
    )
    -- Acute heart failure present for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
              dd.long_title LIKE '%Heart Failure%'
              OR di.icd_code LIKE '428%'
             )
    )
),

presc_class AS (
  SELECT
    ch.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitors'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitors'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
      ELSE NULL
    END AS class,
    p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  JOIN cohort_admissions AS ch
    ON p.hadm_id = ch.hadm_id
  WHERE LOWER(p.drug) IS NOT NULL
    -- keep only those mappings that belong to the five classes of interest
    AND CASE
          WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
          WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
          WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitors'
          WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitors'
          WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
          ELSE NULL
        END IS NOT NULL
),

flags AS (
  SELECT
    pc.hadm_id,
    pc.class,
    MAX(CASE WHEN pc.starttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS first72_flag,
    MAX(CASE WHEN pc.starttime BETWEEN TIMESTAMP_SUB(ca.dischtime, INTERVAL 48 HOUR) AND ca.dischtime THEN 1 ELSE 0 END) AS last48_flag
  FROM presc_class pc
  JOIN cohort_admissions ca
    ON pc.hadm_id = ca.hadm_id
  GROUP BY pc.hadm_id, pc.class
)

SELECT
  class,
  100.0 * AVG(first72_flag) AS rate_first72,
  100.0 * AVG(last48_flag) AS rate_last48
FROM flags
GROUP BY class
ORDER BY class;