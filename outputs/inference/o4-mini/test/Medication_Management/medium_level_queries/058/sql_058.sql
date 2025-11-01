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
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'E11'))
          OR (d.icd_version = 9  AND STARTS_WITH(d.icd_code, '250'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND STARTS_WITH(d.icd_code, 'I50'))
          OR (d.icd_version = 9  AND STARTS_WITH(d.icd_code, '428'))
        )
    )
),
class_presc AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(rx.drug), r'\bmetformin\b') THEN 'Biguanides'
      WHEN REGEXP_CONTAINS(LOWER(rx.drug), r'\b(glyburide|glipizide|glimepiride)\b') THEN 'Sulfonylureas'
      WHEN REGEXP_CONTAINS(LOWER(rx.drug), r'\b(sitagliptin|linagliptin|saxagliptin|alogliptin)\b') THEN 'DPP4 inhibitors'
      WHEN REGEXP_CONTAINS(LOWER(rx.drug), r'\b(empagliflozin|dapagliflozin|canagliflozin)\b') THEN 'SGLT2 inhibitors'
      WHEN REGEXP_CONTAINS(LOWER(rx.drug), r'\b(liraglutide|exenatide|dulaglutide|semaglutide)\b') THEN 'GLP-1 RA'
      WHEN REGEXP_CONTAINS(LOWER(rx.drug), r'\binsulin\b') THEN 'Insulin'
      ELSE NULL
    END AS drug_class,
    rx.starttime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
      ON c.hadm_id = rx.hadm_id
  WHERE
    rx.starttime BETWEEN c.admittime AND c.dischtime
    AND REGEXP_CONTAINS(LOWER(rx.drug),
      r'metformin|glyburide|glipizide|glimepiride|sitagliptin|linagliptin|saxagliptin|alogliptin|empagliflozin|dapagliflozin|canagliflozin|liraglutide|exenatide|dulaglutide|semaglutide|insulin'
    )
),
class_timing AS (
  SELECT
    c.hadm_id AS hadm_id,
    cp.drug_class,
    MIN(cp.starttime) AS first_start,
    c.admittime,
    c.dischtime
  FROM
    class_presc cp
    JOIN cohort c
      ON cp.hadm_id = c.hadm_id
  GROUP BY
    c.hadm_id,
    cp.drug_class,
    c.admittime,
    c.dischtime
),
class_flags AS (
  SELECT
    hadm_id,
    drug_class,
    IF(
      first_start <= TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR),
      1, 0
    ) AS first12,
    IF(
      first_start >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR)
      AND first_start <= dischtime,
      1, 0
    ) AS last48
  FROM
    class_timing
),
summary AS (
  SELECT
    drug_class,
    COUNTIF(first12 = 1) AS n_first12,
    COUNTIF(last48 = 1) AS n_last48
  FROM
    class_flags
  GROUP BY
    drug_class
),
totals AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS total_adm
  FROM
    cohort
)
SELECT
  s.drug_class AS antidiabetic_class,
  ROUND(100.0 * s.n_first12  / t.total_adm, 1) AS pct_initiated_first_12h,
  ROUND(100.0 * s.n_last48   / t.total_adm, 1) AS pct_initiated_final_48h,
  ROUND(
    100.0 * s.n_last48 / t.total_adm
    - 100.0 * s.n_first12 / t.total_adm
  , 1) AS net_change_pp
FROM
  summary s
  CROSS JOIN totals t
ORDER BY
  antidiabetic_class;