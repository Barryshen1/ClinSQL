WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- female, age 67-77
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    -- has T2DM
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
        AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%type 2 diabetes%'
    )
    -- has heart failure
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
        AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%heart failure%'
    )
),
presc_classified AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%gli%' -- e.g. glyburide, glipizide
           OR LOWER(drug) LIKE '%ide%' -- generic SU names
        THEN 'Sulfonylurea'
      WHEN LOWER(drug) LIKE '%gliptin%' OR LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%linagliptin%' THEN 'DPP-4'
      WHEN LOWER(drug) LIKE '%gliflozin%' OR LOWER(drug) LIKE '%empag%' OR LOWER(drug) LIKE '%dapag%' THEN 'SGLT2'
      WHEN LOWER(drug) LIKE '%tide%' OR LOWER(drug) LIKE '%lutide%' THEN 'GLP-1'
      WHEN LOWER(drug) LIKE '%glitazone%' OR LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class,
    starttime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON c.hadm_id = pr.hadm_id
  WHERE
    pr.starttime IS NOT NULL
),
flags AS (
  SELECT
    hadm_id,
    drug_class,
    MAX(IF(starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR), 1, 0)) AS first12_flag,
    MAX(IF(starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime, 1, 0)) AS final48_flag
  FROM
    presc_classified pc
    JOIN cohort c USING (hadm_id)
  WHERE
    drug_class IS NOT NULL
  GROUP BY
    hadm_id,
    drug_class
),
agg AS (
  SELECT
    drug_class,
    COUNTIF(first12_flag = 1) AS count_first12,
    COUNTIF(final48_flag = 1) AS count_final48
  FROM
    flags
  GROUP BY
    drug_class
),
total AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM
    cohort
)
SELECT
  a.drug_class,
  ROUND(100.0 * a.count_first12 / t.total_admissions, 1) AS first12_pct,
  ROUND(100.0 * a.count_final48 / t.total_admissions, 1) AS final48_pct,
  ROUND(
    100.0 * a.count_final48 / t.total_admissions
    - 100.0 * a.count_first12 / t.total_admissions
  , 1) AS net_change_pp
FROM
  agg a
  CROSS JOIN total t
ORDER BY
  drug_class;