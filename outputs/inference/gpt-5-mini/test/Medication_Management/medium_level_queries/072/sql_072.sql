WITH
-- Cohort: male inpatients age 79-89 with both type 2 diabetes and heart failure diagnoses in the same admission
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- has type 2 diabetes diagnosis during this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code
        AND d.icd_version = di.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- ICD-10 E11* (type 2 diabetes)
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
          -- ICD-9 250* (diabetes mellitus; includes type 2 codes in many datasets)
          OR (d.icd_version = 9 AND d.icd_code LIKE '250%')
          -- or text mentions type 2 / diabetes
          OR (LOWER(COALESCE(di.long_title, '')) LIKE '%type 2%' AND LOWER(COALESCE(di.long_title, '')) LIKE '%diabet%')
          OR (LOWER(COALESCE(di.long_title, '')) LIKE '%diabetes%')
        )
    )
    -- has heart failure diagnosis during this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di2
        ON d2.icd_code = di2.icd_code
        AND d2.icd_version = di2.icd_version
      WHERE d2.hadm_id = a.hadm_id
        AND (
          -- ICD-10 I50* (heart failure)
          (d2.icd_version = 10 AND d2.icd_code LIKE 'I50%')
          -- ICD-9 428* (heart failure)
          OR (d2.icd_version = 9 AND d2.icd_code LIKE '428%')
          -- or text mentions heart failure
          OR (LOWER(COALESCE(di2.long_title, '')) LIKE '%heart failure%')
        )
    )
),
-- GLP-1 prescriptions for inpatients: match common GLP-1 agents by drug name (case-insensitive)
glp_prescriptions AS (
  SELECT
    p.hadm_id,
    p.starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE
    p.starttime IS NOT NULL
    AND (
      LOWER(COALESCE(p.drug, '')) LIKE '%liraglutide%'    -- Victoza
      OR LOWER(COALESCE(p.drug, '')) LIKE '%exenatide%'   -- Byetta, Bydureon
      OR LOWER(COALESCE(p.drug, '')) LIKE '%semaglutide%' -- Ozempic, Rybelsus, Wegovy
      OR LOWER(COALESCE(p.drug, '')) LIKE '%dulaglutide%' -- Trulicity
      OR LOWER(COALESCE(p.drug, '')) LIKE '%albiglutide%' -- (Tanzeum - rare)
      OR LOWER(COALESCE(p.drug, '')) LIKE '%lixisenatide%'-- Adlyxin
      OR LOWER(COALESCE(p.drug, '')) LIKE '%tirzepatide%' -- Mounjaro (GIP/GLP-1 agonist)
    )
),
-- For each admission in the cohort, determine whether a GLP-1 prescription was started in the first 12 hours and/or final 24 hours
per_admission AS (
  SELECT
    c.hadm_id,
    MAX(CASE
        WHEN gp.starttime >= c.admittime
         AND gp.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR) THEN 1
        ELSE 0
    END) AS started_first12,
    MAX(CASE
        WHEN gp.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
         AND gp.starttime <= c.dischtime THEN 1
        ELSE 0
    END) AS started_last24
  FROM
    cohort c
  LEFT JOIN
    glp_prescriptions gp
  ON
    gp.hadm_id = c.hadm_id
  GROUP BY
    c.hadm_id
)

SELECT
  COUNT(*) AS n_admissions_in_cohort,
  SUM(started_first12) AS n_started_first12,
  ROUND(100.0 * SAFE_DIVIDE(SUM(started_first12), COUNT(*)), 2) AS pct_started_first12,
  SUM(started_last24) AS n_started_last24,
  ROUND(100.0 * SAFE_DIVIDE(SUM(started_last24), COUNT(*)), 2) AS pct_started_last24,
  ROUND(
    100.0 * (
      SAFE_DIVIDE(SUM(started_last24), COUNT(*))
      - SAFE_DIVIDE(SUM(started_first12), COUNT(*))
    ),
    2
  ) AS net_percentage_point_change_final24_minus_first12
FROM
  per_admission;