WITH
-- Cohort: male inpatients aged 64-74 with both diabetes and acute heart failure diagnoses on the admission
cohort_admissions AS (
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
    AND p.anchor_age BETWEEN 64 AND 74
    -- must have a diabetes diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
        ON dx.icd_code = dic.icd_code
        AND dx.icd_version = dic.icd_version
      WHERE dx.hadm_id = a.hadm_id
        AND LOWER(dic.long_title) LIKE '%diabetes%'
    )
    -- must have an acute/acute-on/ or congestive heart failure diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
        ON dx.icd_code = dic.icd_code
        AND dx.icd_version = dic.icd_version
      WHERE dx.hadm_id = a.hadm_id
        AND LOWER(dic.long_title) LIKE '%heart failure%'
        AND (
          LOWER(dic.long_title) LIKE '%acute%'
          OR LOWER(dic.long_title) LIKE '%acutely%'
          OR LOWER(dic.long_title) LIKE '%congestive%'
        )
    )
),

-- Map prescriptions to antidiabetic classes and keep only those with a starttime during the admission
presc_mapped AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.drug,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'(insulin)') THEN 'Insulin'
      WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'(metformin)') THEN 'Metformin'
      WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'(glipizide|glyburide|glibenclamide|glimepiride|tolbutamide|chlorpropamide|sulfonylurea)') THEN 'Sulfonylurea'
      WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'(sitagliptin|linagliptin|saxagliptin|alogliptin|vildagliptin|dpp[\- ]?4|dpp4)') THEN 'DPP4'
      WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'(empagliflozin|canagliflozin|dapagliflozin|ertugliflozin|sglt2)') THEN 'SGLT2'
      WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'(liraglutide|exenatide|semaglutide|dulaglutide|albiglutide|lixisenatide|glp[\- ]?1|glp1)') THEN 'GLP1'
      WHEN REGEXP_CONTAINS(LOWER(pr.drug), r'(pioglitazone|rosiglitazone|thiazolidinedione|tzd|tzds)') THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN cohort_admissions ca
      ON pr.hadm_id = ca.hadm_id
  WHERE
    pr.starttime IS NOT NULL
    -- only consider prescriptions that start during the admission
    AND pr.starttime >= ca.admittime
    AND pr.starttime <= ca.dischtime
    -- map only relevant antidiabetic classes
    AND (
      REGEXP_CONTAINS(LOWER(pr.drug), r'(insulin)')
      OR REGEXP_CONTAINS(LOWER(pr.drug), r'(metformin)')
      OR REGEXP_CONTAINS(LOWER(pr.drug), r'(glipizide|glyburide|glibenclamide|glimepiride|tolbutamide|chlorpropamide|sulfonylurea)')
      OR REGEXP_CONTAINS(LOWER(pr.drug), r'(sitagliptin|linagliptin|saxagliptin|alogliptin|vildagliptin|dpp[\- ]?4|dpp4)')
      OR REGEXP_CONTAINS(LOWER(pr.drug), r'(empagliflozin|canagliflozin|dapagliflozin|ertugliflozin|sglt2)')
      OR REGEXP_CONTAINS(LOWER(pr.drug), r'(liraglutide|exenatide|semaglutide|dulaglutide|albiglutide|lixisenatide|glp[\- ]?1|glp1)')
      OR REGEXP_CONTAINS(LOWER(pr.drug), r'(pioglitazone|rosiglitazone|thiazolidinedione|tzd|tzds)')
    )
),

-- Earliest in-admission starttime per hadm_id and drug class (represents initiation during admission)
earliest_initiation AS (
  SELECT
    hadm_id,
    drug_class,
    MIN(starttime) AS first_starttime
  FROM presc_mapped
  WHERE drug_class IS NOT NULL
  GROUP BY hadm_id, drug_class
),

-- Determine whether earliest initiation falls in first 12h or final 48h for that admission
initiations_timing AS (
  SELECT
    ei.hadm_id,
    ei.drug_class,
    ei.first_starttime,
    ca.admittime,
    ca.dischtime,
    -- boolean flags
    CASE WHEN ei.first_starttime <= TIMESTAMP_ADD(ca.admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END AS in_first_12h,
    CASE WHEN ei.first_starttime >= TIMESTAMP_SUB(ca.dischtime, INTERVAL 48 HOUR)
              AND ei.first_starttime <= ca.dischtime THEN 1 ELSE 0 END AS in_final_48h
  FROM
    earliest_initiation ei
    JOIN cohort_admissions ca
      ON ei.hadm_id = ca.hadm_id
)

-- Final aggregation: counts and percentages per drug class
SELECT
  it.drug_class,
  COUNT(DISTINCT CASE WHEN it.in_first_12h = 1 THEN it.hadm_id END) AS n_first_12h,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN it.in_first_12h = 1 THEN it.hadm_id END) / cohort.total_admissions, 1) AS pct_first_12h,
  COUNT(DISTINCT CASE WHEN it.in_final_48h = 1 THEN it.hadm_id END) AS n_final_48h,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN it.in_final_48h = 1 THEN it.hadm_id END) / cohort.total_admissions, 1) AS pct_final_48h,
  cohort.total_admissions
FROM
  initiations_timing it
  CROSS JOIN (
    -- denominator: total distinct admissions in cohort
    SELECT COUNT(DISTINCT hadm_id) AS total_admissions
    FROM cohort_admissions
  ) AS cohort
GROUP BY
  it.drug_class,
  cohort.total_admissions
ORDER BY
  it.drug_class;