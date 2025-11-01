WITH cohort AS (
  SELECT
    adm.hadm_id,
    adm.subject_id,
    adm.admittime,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    -- will filter for diagnoses below
),
dx AS (
  -- find admissions with both T2DM and heart failure
  SELECT
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    ( (d.icd_version = 9 AND d.icd_code LIKE '250%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%') )
    OR
    ( (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%') )
  GROUP BY d.hadm_id
  HAVING
    -- must have at least one code for diabetes and one for heart failure
    COUNTIF(
      (d.icd_version = 9 AND d.icd_code LIKE '250%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
    ) >= 1
    AND
    COUNTIF(
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    ) >= 1
),
exposures AS (
  SELECT
    c.hadm_id,
    -- Early exposure flags (first 72h)
    MAX(CASE WHEN LOWER(p.drug) LIKE '%metformin%'
             AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
         THEN 1 ELSE 0 END) AS early_metformin,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%glipizide%'
                   OR LOWER(p.drug) LIKE '%glyburide%'
                   OR LOWER(p.drug) LIKE '%glimepiride%')
             AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
         THEN 1 ELSE 0 END) AS early_sulfonylurea,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%sitagliptin%'
                   OR LOWER(p.drug) LIKE '%saxagliptin%'
                   OR LOWER(p.drug) LIKE '%linagliptin%')
             AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
         THEN 1 ELSE 0 END) AS early_dpp4,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%dapagliflozin%'
                   OR LOWER(p.drug) LIKE '%empagliflozin%'
                   OR LOWER(p.drug) LIKE '%canagliflozin%')
             AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
         THEN 1 ELSE 0 END) AS early_sglt2,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%pioglitazone%'
                   OR LOWER(p.drug) LIKE '%rosiglitazone%')
             AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
         THEN 1 ELSE 0 END) AS early_tzd,
    -- Late exposure flags (final 48h)
    MAX(CASE WHEN LOWER(p.drug) LIKE '%metformin%'
             AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
         THEN 1 ELSE 0 END) AS late_metformin,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%glipizide%'
                   OR LOWER(p.drug) LIKE '%glyburide%'
                   OR LOWER(p.drug) LIKE '%glimepiride%')
             AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
         THEN 1 ELSE 0 END) AS late_sulfonylurea,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%sitagliptin%'
                   OR LOWER(p.drug) LIKE '%saxagliptin%'
                   OR LOWER(p.drug) LIKE '%linagliptin%')
             AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
         THEN 1 ELSE 0 END) AS late_dpp4,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%dapagliflozin%'
                   OR LOWER(p.drug) LIKE '%empagliflozin%'
                   OR LOWER(p.drug) LIKE '%canagliflozin%')
             AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
         THEN 1 ELSE 0 END) AS late_sglt2,
    MAX(CASE WHEN (LOWER(p.drug) LIKE '%pioglitazone%'
                   OR LOWER(p.drug) LIKE '%rosiglitazone%')
             AND p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
         THEN 1 ELSE 0 END) AS late_tzd
  FROM cohort AS c
  JOIN dx
    ON c.hadm_id = dx.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id
),
n AS (
  SELECT COUNT(*) AS total_patients
  FROM exposures
)
SELECT
  class,
  ROUND(100 * early_count / total_patients, 1)  AS pct_early,
  ROUND(100 * late_count  / total_patients, 1)  AS pct_late,
  ROUND(100 * (early_count - late_count) / total_patients, 1) AS pp_difference
FROM (
  SELECT
    'Metformin' AS class,
    SUM(early_metformin) AS early_count,
    SUM(late_metformin)  AS late_count
  FROM exposures
  UNION ALL
  SELECT
    'Sulfonylurea' AS class,
    SUM(early_sulfonylurea),
    SUM(late_sulfonylurea)
  FROM exposures
  UNION ALL
  SELECT
    'DPP4 inhibitor' AS class,
    SUM(early_dpp4),
    SUM(late_dpp4)
  FROM exposures
  UNION ALL
  SELECT
    'SGLT2 inhibitor' AS class,
    SUM(early_sglt2),
    SUM(late_sglt2)
  FROM exposures
  UNION ALL
  SELECT
    'TZD' AS class,
    SUM(early_tzd),
    SUM(late_tzd)
  FROM exposures
) AS class_counts
CROSS JOIN n
ORDER BY class;