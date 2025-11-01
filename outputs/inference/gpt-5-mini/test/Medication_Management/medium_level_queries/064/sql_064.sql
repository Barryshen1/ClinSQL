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
  WHERE
    p.anchor_age BETWEEN 71 AND 81
    AND p.gender = 'M'  -- filter to males (change if desired)
    AND a.hadm_id IS NOT NULL
    -- has diabetes diagnosis on this admission (ICD9/10 long_title contains 'diabetes')
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    -- has heart failure diagnosis on this admission (long_title contains 'heart failure')
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),

-- For each admission in the cohort, get the earliest prescription starttime for each medication class
med_first_per_admission AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MIN(CASE WHEN LOWER(p.drug) LIKE '%metformin%' THEN p.starttime END) AS met_min,
    MIN(CASE WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%'
             OR LOWER(p.drug) LIKE '%tolbutamide%' OR LOWER(p.drug) LIKE '%chlorpropamide%' OR LOWER(p.drug) LIKE '%gliclazide%'
         THEN p.starttime END) AS sulfonyl_min,
    MIN(CASE WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%'
         THEN p.starttime END) AS dpp4_min,
    MIN(CASE WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%'
         THEN p.starttime END) AS sglt2_min,
    MIN(CASE WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%'
         THEN p.starttime END) AS thiazolid_min
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON p.hadm_id = c.hadm_id
      -- consider only prescriptions that occur during the admission
      AND p.starttime >= c.admittime
      AND p.starttime < c.dischtime
  GROUP BY
    c.hadm_id, c.admittime, c.dischtime
),

-- Compute counts and percentages per class for the two windows
aggregated AS (
  SELECT
    COUNT(*) AS total_admissions,

    -- Metformin: first 72h
    SUM(CASE WHEN met_min IS NOT NULL AND met_min >= admittime AND met_min < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS met_first72_count,
    -- Metformin: last 48h
    SUM(CASE WHEN met_min IS NOT NULL AND met_min >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND met_min < dischtime THEN 1 ELSE 0 END) AS met_last48_count,

    -- Sulfonylureas
    SUM(CASE WHEN sulfonyl_min IS NOT NULL AND sulfonyl_min >= admittime AND sulfonyl_min < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS sulf_first72_count,
    SUM(CASE WHEN sulfonyl_min IS NOT NULL AND sulfonyl_min >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND sulfonyl_min < dischtime THEN 1 ELSE 0 END) AS sulf_last48_count,

    -- DPP-4 inhibitors
    SUM(CASE WHEN dpp4_min IS NOT NULL AND dpp4_min >= admittime AND dpp4_min < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS dpp4_first72_count,
    SUM(CASE WHEN dpp4_min IS NOT NULL AND dpp4_min >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND dpp4_min < dischtime THEN 1 ELSE 0 END) AS dpp4_last48_count,

    -- SGLT2 inhibitors
    SUM(CASE WHEN sglt2_min IS NOT NULL AND sglt2_min >= admittime AND sglt2_min < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS sglt2_first72_count,
    SUM(CASE WHEN sglt2_min IS NOT NULL AND sglt2_min >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND sglt2_min < dischtime THEN 1 ELSE 0 END) AS sglt2_last48_count,

    -- Thiazolidinediones
    SUM(CASE WHEN thiazolid_min IS NOT NULL AND thiazolid_min >= admittime AND thiazolid_min < TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS thiaz_first72_count,
    SUM(CASE WHEN thiazolid_min IS NOT NULL AND thiazolid_min >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AND thiazolid_min < dischtime THEN 1 ELSE 0 END) AS thiaz_last48_count

  FROM
    med_first_per_admission
)

-- Unpivot results into one row per medication class with counts and percentages
SELECT
  med_class,
  count_initiated AS initiated_count,
  ROUND(100.0 * SAFE_DIVIDE(count_initiated, total_admissions), 2) AS initiated_pct,
  window_label
FROM (
  SELECT a.total_admissions, 'Metformin' AS med_class, a.met_first72_count AS count_initiated, 'first_72h' AS window_label FROM aggregated a
  UNION ALL
  SELECT a.total_admissions, 'Metformin' AS med_class, a.met_last48_count AS count_initiated, 'last_48h' AS window_label FROM aggregated a
  UNION ALL
  SELECT a.total_admissions, 'Sulfonylureas' AS med_class, a.sulf_first72_count AS count_initiated, 'first_72h' AS window_label FROM aggregated a
  UNION ALL
  SELECT a.total_admissions, 'Sulfonylureas' AS med_class, a.sulf_last48_count AS count_initiated, 'last_48h' AS window_label FROM aggregated a
  UNION ALL
  SELECT a.total_admissions, 'DPP-4 inhibitors' AS med_class, a.dpp4_first72_count AS count_initiated, 'first_72h' AS window_label FROM aggregated a
  UNION ALL
  SELECT a.total_admissions, 'DPP-4 inhibitors' AS med_class, a.dpp4_last48_count AS count_initiated, 'last_48h' AS window_label FROM aggregated a
  UNION ALL
  SELECT a.total_admissions, 'SGLT2 inhibitors' AS med_class, a.sglt2_first72_count AS count_initiated, 'first_72h' AS window_label FROM aggregated a
  UNION ALL
  SELECT a.total_admissions, 'SGLT2 inhibitors' AS med_class, a.sglt2_last48_count AS count_initiated, 'last_48h' AS window_label FROM aggregated a
  UNION ALL
  SELECT a.total_admissions, 'Thiazolidinediones' AS med_class, a.thiaz_first72_count AS count_initiated, 'first_72h' AS window_label FROM aggregated a
  UNION ALL
  SELECT a.total_admissions, 'Thiazolidinediones' AS med_class, a.thiaz_last48_count AS count_initiated, 'last_48h' AS window_label FROM aggregated a
) t
ORDER BY med_class, window_label;