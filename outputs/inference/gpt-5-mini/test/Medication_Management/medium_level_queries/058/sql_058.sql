WITH cohort AS (
  -- admissions for male patients age 36-46 with both T2DM and heart failure diagnoses in the same hadm_id
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND a.hadm_id IS NOT NULL
    AND EXISTS (
      -- T2DM: ICD-10 E11* OR long_title contains diabetes + type 2 / type ii
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
        ON d.icd_code = dic.icd_code
        AND d.icd_version = dic.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND LOWER(d.icd_code) LIKE 'e11%')
          OR (
            LOWER(dic.long_title) LIKE '%diabetes%'
            AND (
              LOWER(dic.long_title) LIKE '%type 2%'
              OR LOWER(dic.long_title) LIKE '%type ii%'
            )
          )
        )
      LIMIT 1
    )
    AND EXISTS (
      -- Heart failure: ICD-10 I50* OR long_title contains 'heart failure'
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
        ON d.icd_code = dic.icd_code
        AND d.icd_version = dic.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND LOWER(d.icd_code) LIKE 'i50%')
          OR LOWER(dic.long_title) LIKE '%heart failure%'
        )
      LIMIT 1
    )
),

mapped_prescriptions AS (
  -- Map prescriptions to antidiabetic classes and keep only those occurring during the admission
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.drug,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%glargine%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%detemir%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%aspart%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%lispro%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%degludec%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%glyburide%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' THEN 'DPP4 inhibitor'
      WHEN LOWER(p.drug) LIKE '%linagliptin%' THEN 'DPP4 inhibitor'
      WHEN LOWER(p.drug) LIKE '%saxagliptin%' THEN 'DPP4 inhibitor'
      WHEN LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP4 inhibitor'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' THEN 'GLP1 receptor agonist'
      WHEN LOWER(p.drug) LIKE '%exenatide%' THEN 'GLP1 receptor agonist'
      WHEN LOWER(p.drug) LIKE '%dulaglutide%' THEN 'GLP1 receptor agonist'
      WHEN LOWER(p.drug) LIKE '%semaglutide%' THEN 'GLP1 receptor agonist'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(p.drug) LIKE '%dapagliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' THEN 'TZD'
      WHEN LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      WHEN LOWER(p.drug) LIKE '%repaglinide%' THEN 'Meglitinide'
      WHEN LOWER(p.drug) LIKE '%nateglinide%' THEN 'Meglitinide'
      WHEN LOWER(p.drug) LIKE '%acarbose%' THEN 'Alpha-glucosidase inhibitor'
      ELSE NULL
    END AS drug_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort c
    ON p.hadm_id = c.hadm_id
  WHERE
    p.starttime IS NOT NULL
    -- only medications administered/ordered during the admission window
    AND p.starttime >= c.admittime
    AND p.starttime <= c.dischtime
),

earliest_class_start AS (
  -- For each admission and drug class, find the earliest starttime in the admission (i.e., initiation for that class)
  SELECT
    hadm_id,
    drug_class,
    MIN(starttime) AS first_starttime
  FROM mapped_prescriptions
  WHERE drug_class IS NOT NULL
  GROUP BY hadm_id, drug_class
),

per_class_windows AS (
  -- Determine whether that earliest start falls in first 12h and/or final 48h
  SELECT
    e.hadm_id,
    e.drug_class,
    e.first_starttime,
    c.admittime,
    c.dischtime,
    -- boolean flags for windows
    CASE
      WHEN e.first_starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR) THEN 1
      ELSE 0
    END AS in_first_12h,
    CASE
      WHEN e.first_starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1
      ELSE 0
    END AS in_last_48h
  FROM earliest_class_start e
  JOIN cohort c
    ON e.hadm_id = c.hadm_id
),

class_aggregates AS (
  -- Aggregate counts per class across cohort
  SELECT
    drug_class,
    SUM(in_first_12h) AS first12_count,
    SUM(in_last_48h) AS last48_count
  FROM per_class_windows
  GROUP BY drug_class
),

cohort_size AS (
  -- Denominator: number of unique admissions in the cohort
  SELECT COUNT(DISTINCT hadm_id) AS n_hadm
  FROM cohort
)

SELECT
  ca.drug_class AS antidiabetic_class,
  ca.first12_count,
  ROUND(100.0 * ca.first12_count / cs.n_hadm, 2) AS first12_pct,
  ca.last48_count,
  ROUND(100.0 * ca.last48_count / cs.n_hadm, 2) AS last48_pct,
  ROUND(100.0 * ca.last48_count / cs.n_hadm - 100.0 * ca.first12_count / cs.n_hadm, 2) AS net_change_pp,
  cs.n_hadm AS cohort_admission_count
FROM
  class_aggregates ca
CROSS JOIN
  cohort_size cs
ORDER BY
  net_change_pp DESC, antidiabetic_class;