WITH
-- 1) Define cohort: female admissions age 67-77 with both T2DM and HF diagnoses for that hadm_id
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
    USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- ensure T2DM exists for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- common ICD10/ICD9 prefix checks OR textual match
          LOWER(COALESCE(dicd.long_title, '')) LIKE '%type 2%' AND LOWER(COALESCE(dicd.long_title, '')) LIKE '%diabet%'
          OR d.icd_code LIKE 'E11%'  -- ICD10 type 2 DM
          OR d.icd_code LIKE '250%'  -- ICD9 diabetes codes
        )
    )
    -- ensure Heart Failure exists for this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(COALESCE(dicd.long_title, '')) LIKE '%heart failure%'
          OR d.icd_code LIKE 'I50%'  -- ICD10 heart failure
          OR d.icd_code LIKE '428%'  -- ICD9 heart failure
        )
    )
),

-- 2) Map prescriptions to drug classes (only prescriptions within the admission)
presc_class AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.starttime,
    CASE
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(p.drug, '')), r'INSULIN|GLARGINE|DEGLUDEC|DETEMIR|NPH|HUMULIN|NOVOLIN|LISPRO|GLULISINE') THEN 'insulin'
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(p.drug, '')), r'METFORMIN') THEN 'metformin'
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(p.drug, '')), r'GLIPIZIDE|GLYBURIDE|GLIMEPIRIDE|GLIBENCLAMIDE|TOLBUTAMIDE|CHLORPROPAMIDE') THEN 'sulfonylurea'
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(p.drug, '')), r'SITAGLIPTIN|SAXAGLIPTIN|LINAGLIPTIN|ALOGLIPTIN|VILDAGLIPTIN') THEN 'dpp4'
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(p.drug, '')), r'CANAGLIFLOZIN|DAPAGLIFLOZIN|EMPAGLIFLOZIN|ERTUGLIFLOZIN') THEN 'sglt2'
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(p.drug, '')), r'LIRAGLUTIDE|EXENATIDE|DULAGLUTIDE|SEMAGLUTIDE|ALBIGLUTIDE|LIXISENATIDE') THEN 'glp1'
      WHEN REGEXP_CONTAINS(UPPER(COALESCE(p.drug, '')), r'PIOGLITAZONE|ROSIGLITAZONE') THEN 'tzd'
      ELSE NULL
    END AS drug_class
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
  WHERE
    p.starttime IS NOT NULL
    AND p.starttime BETWEEN c.admittime AND c.dischtime
),

-- 3) For each admission and class, keep earliest starttime (initiation time during that admission)
first_inits AS (
  SELECT
    hadm_id,
    drug_class,
    MIN(starttime) AS init_time,
    MIN(admittime) AS admittime,
    MAX(dischtime) AS dischtime
  FROM presc_class
  WHERE drug_class IS NOT NULL
  GROUP BY hadm_id, drug_class
),

-- 4) For every hadm_id & class determine whether the earliest initiation falls in first 12h and/or final 48h
init_flags AS (
  SELECT
    fi.hadm_id,
    fi.drug_class,
    fi.init_time,
    fi.admittime,
    fi.dischtime,
    CASE WHEN fi.init_time <= TIMESTAMP_ADD(fi.admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END AS in_first_12h,
    CASE WHEN fi.init_time >= TIMESTAMP_SUB(fi.dischtime, INTERVAL 48 HOUR)
              AND fi.init_time <= fi.dischtime THEN 1 ELSE 0 END AS in_final_48h
  FROM first_inits fi
),

-- 5) Aggregate counts per class
class_counts AS (
  SELECT
    ic.drug_class,
    COUNT(DISTINCT CASE WHEN ic.in_first_12h = 1 THEN ic.hadm_id END) AS n_first12,
    COUNT(DISTINCT CASE WHEN ic.in_final_48h = 1 THEN ic.hadm_id END) AS n_final48
  FROM init_flags ic
  GROUP BY ic.drug_class
),

-- 6) Ensure all requested classes appear even if counts are zero
classes AS (
  SELECT 'insulin' AS drug_class UNION ALL
  SELECT 'metformin' UNION ALL
  SELECT 'sulfonylurea' UNION ALL
  SELECT 'dpp4' UNION ALL
  SELECT 'sglt2' UNION ALL
  SELECT 'glp1' UNION ALL
  SELECT 'tzd'
),

-- 7) Total denominator (number of admissions in cohort)
den AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_admissions
  FROM cohort
)

SELECT
  c.drug_class,
  COALESCE(cc.n_first12, 0) AS n_first12,
  ROUND(100.0 * COALESCE(cc.n_first12, 0) / d.total_admissions, 2) AS pct_first12,
  COALESCE(cc.n_final48, 0) AS n_final48,
  ROUND(100.0 * COALESCE(cc.n_final48, 0) / d.total_admissions, 2) AS pct_final48,
  ROUND(
    100.0 * COALESCE(cc.n_final48, 0) / d.total_admissions
    - 100.0 * COALESCE(cc.n_first12, 0) / d.total_admissions
  , 2) AS net_pct_points
FROM
  classes c
LEFT JOIN
  class_counts cc
  ON c.drug_class = cc.drug_class
CROSS JOIN
  den d
ORDER BY
  -- keep a clinically intuitive order
  CASE c.drug_class
    WHEN 'insulin' THEN 1
    WHEN 'metformin' THEN 2
    WHEN 'sulfonylurea' THEN 3
    WHEN 'dpp4' THEN 4
    WHEN 'sglt2' THEN 5
    WHEN 'glp1' THEN 6
    WHEN 'tzd' THEN 7
    ELSE 99 END;