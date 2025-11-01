WITH cohort AS (
  -- Female patients age 69-79 with T2DM and HF in a given admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    -- limit to actual inpatient stays
    AND a.hospital_expire_flag IN (0,1)
    -- ensure both T2DM and HF diagnoses in this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
             -- T2DM ICD-9 or ICD-10
             (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '250'))
          OR (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'E11'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
             -- HF ICD-9 or ICD-10
             (d.icd_version = 9 AND STARTS_WITH(d.icd_code, '428'))
          OR (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I50'))
        )
    )
),
total AS (
  -- total number of admissions in the cohort
  SELECT
    COUNT(DISTINCT hadm_id) AS n_admissions
  FROM cohort
),
presc AS (
  -- prescriptions within first and last 72 hours
  SELECT
    c.hadm_id,
    LOWER(p.drug) AS drug_lower,
    p.starttime,
    c.admittime,
    c.dischtime,
    -- flag for first 72h vs last 72h
    CASE
      WHEN p.starttime BETWEEN c.admittime
                          AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
      THEN 'first72'
    WHEN p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
                          AND c.dischtime
      THEN 'last72'
      ELSE NULL
    END AS period
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
  WHERE
    -- only keep prescriptions in one of our two windows
    p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    OR p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime
),
class_flags AS (
  -- identify drug class flags
  SELECT
    hadm_id,
    period,
    MAX(IF(drug_lower LIKE '%insulin%', 1, 0)) AS insulin,
    MAX(IF(drug_lower LIKE '%metformin%', 1, 0)) AS metformin,
    MAX(IF(drug_lower LIKE '%glipizide%' OR drug_lower LIKE '%glyburide%' OR drug_lower LIKE '%glimepiride%', 1, 0)) AS sulfonylurea,
    MAX(IF(drug_lower LIKE '%sitagliptin%' OR drug_lower LIKE '%saxagliptin%' OR drug_lower LIKE '%linagliptin%', 1, 0)) AS dpp4,
    MAX(IF(drug_lower LIKE '%canagliflozin%' OR drug_lower LIKE '%dapagliflozin%' OR drug_lower LIKE '%empagliflozin%', 1, 0)) AS sglt2,
    MAX(IF(drug_lower LIKE '%exenatide%' OR drug_lower LIKE '%liraglutide%' OR drug_lower LIKE '%dulaglutide%' OR drug_lower LIKE '%semaglutide%', 1, 0)) AS glp1,
    MAX(IF(drug_lower LIKE '%pioglitazone%' OR drug_lower LIKE '%rosiglitazone%', 1, 0)) AS tzd
  FROM presc
  WHERE period IS NOT NULL
  GROUP BY hadm_id, period
),
agg AS (
  -- aggregate counts by period and class
  SELECT
    period,
    SUM(insulin)    AS insulin_cnt,
    SUM(metformin)  AS metformin_cnt,
    SUM(sulfonylurea) AS sulfonylurea_cnt,
    SUM(dpp4)       AS dpp4_cnt,
    SUM(sglt2)      AS sglt2_cnt,
    SUM(glp1)       AS glp1_cnt,
    SUM(tzd)        AS tzd_cnt
  FROM class_flags
  GROUP BY period
)
SELECT
  a.period,
  ROUND(100.0 * a.insulin_cnt    / t.n_admissions, 1) AS pct_insulin,
  ROUND(100.0 * a.metformin_cnt  / t.n_admissions, 1) AS pct_metformin,
  ROUND(100.0 * a.sulfonylurea_cnt / t.n_admissions,1) AS pct_sulfonylurea,
  ROUND(100.0 * a.dpp4_cnt       / t.n_admissions, 1) AS pct_dpp4,
  ROUND(100.0 * a.sglt2_cnt      / t.n_admissions, 1) AS pct_sglt2,
  ROUND(100.0 * a.glp1_cnt       / t.n_admissions, 1) AS pct_glp1,
  ROUND(100.0 * a.tzd_cnt        / t.n_admissions, 1) AS pct_tzd
FROM
  agg a
  CROSS JOIN total t
ORDER BY
  a.period;