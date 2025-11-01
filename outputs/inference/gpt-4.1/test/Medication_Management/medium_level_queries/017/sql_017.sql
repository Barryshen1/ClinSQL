WITH
-- 1. Identify cohort: female, age 37-47, diabetes AND heart failure, ICU stay >=144h
cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 37 AND 47
    AND icu.los >= 144
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
      WHERE d1.subject_id = icu.subject_id AND d1.hadm_id = icu.hadm_id
        AND (
          -- Diabetes ICD-10: E08-E13, ICD-9: 250
          (d1.icd_version = 10 AND REGEXP_CONTAINS(d1.icd_code, r'^E0[8-9]|^E1[0-3]'))
          OR (d1.icd_version = 9 AND d1.icd_code LIKE '250%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.subject_id = icu.subject_id AND d2.hadm_id = icu.hadm_id
        AND (
          -- Heart failure ICD-10: I50, ICD-9: 428
          (d2.icd_version = 10 AND d2.icd_code LIKE 'I50%')
          OR (d2.icd_version = 9 AND d2.icd_code LIKE '428%')
        )
    )
),

-- 2. Drug class definitions (lower-case for matching)
drug_classes AS (
  SELECT 'antidiabetic' AS drug_class, 'insulin' AS drug UNION ALL
  SELECT 'antidiabetic', 'metformin' UNION ALL
  SELECT 'antidiabetic', 'glipizide' UNION ALL
  SELECT 'antidiabetic', 'glyburide' UNION ALL
  SELECT 'antidiabetic', 'glimepiride' UNION ALL
  SELECT 'antidiabetic', 'pioglitazone' UNION ALL
  SELECT 'antidiabetic', 'sitagliptin' UNION ALL
  SELECT 'antidiabetic', 'liraglutide' UNION ALL
  SELECT 'antidiabetic', 'exenatide' UNION ALL
  SELECT 'antidiabetic', 'empagliflozin' UNION ALL
  SELECT 'antidiabetic', 'canagliflozin' UNION ALL
  SELECT 'beta_blocker', 'metoprolol' UNION ALL
  SELECT 'beta_blocker', 'atenolol' UNION ALL
  SELECT 'beta_blocker', 'carvedilol' UNION ALL
  SELECT 'beta_blocker', 'bisoprolol' UNION ALL
  SELECT 'beta_blocker', 'propranolol' UNION ALL
  SELECT 'beta_blocker', 'labetalol' UNION ALL
  SELECT 'ace_arb_arni', 'lisinopril' UNION ALL
  SELECT 'ace_arb_arni', 'enalapril' UNION ALL
  SELECT 'ace_arb_arni', 'ramipril' UNION ALL
  SELECT 'ace_arb_arni', 'captopril' UNION ALL
  SELECT 'ace_arb_arni', 'losartan' UNION ALL
  SELECT 'ace_arb_arni', 'valsartan' UNION ALL
  SELECT 'ace_arb_arni', 'candesartan' UNION ALL
  SELECT 'ace_arb_arni', 'irbesartan' UNION ALL
  SELECT 'ace_arb_arni', 'olmesartan' UNION ALL
  SELECT 'ace_arb_arni', 'sacubitril' UNION ALL
  SELECT 'ace_arb_arni', 'sacubitril/valsartan' UNION ALL
  SELECT 'loop_diuretic', 'furosemide' UNION ALL
  SELECT 'loop_diuretic', 'bumetanide' UNION ALL
  SELECT 'loop_diuretic', 'torsemide'
),

-- 3. Medication administration in first/final 72h (from EMAR)
emar_drugs AS (
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    dc.drug_class,
    MIN(CASE WHEN e.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS in_first_72h,
    MIN(CASE WHEN e.charttime BETWEEN DATETIME_SUB(c.outtime, INTERVAL 72 HOUR) AND c.outtime THEN 1 ELSE 0 END) AS in_final_72h
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  JOIN
    drug_classes dc
    ON LOWER(e.medication) LIKE CONCAT('%', dc.drug, '%')
  GROUP BY
    c.stay_id, c.subject_id, c.hadm_id, dc.drug_class
),

-- 4. For stays with no EMAR, fallback to prescriptions (orders)
presc_drugs AS (
  SELECT
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    dc.drug_class,
    MIN(CASE WHEN p.starttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS in_first_72h,
    MIN(CASE WHEN p.starttime BETWEEN DATETIME_SUB(c.outtime, INTERVAL 72 HOUR) AND c.outtime THEN 1 ELSE 0 END) AS in_final_72h
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  JOIN
    drug_classes dc
    ON LOWER(p.drug) LIKE CONCAT('%', dc.drug, '%')
  GROUP BY
    c.stay_id, c.subject_id, c.hadm_id, dc.drug_class
),

-- 5. Union EMAR and prescriptions, preferring EMAR if available
all_drugs AS (
  SELECT * FROM emar_drugs
  UNION ALL
  SELECT * FROM presc_drugs
),

-- 6. For each stay and drug class, aggregate exposure
drug_exposure AS (
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    drug_class,
    MAX(in_first_72h) AS in_first_72h,
    MAX(in_final_72h) AS in_final_72h
  FROM
    all_drugs
  GROUP BY
    stay_id, subject_id, hadm_id, drug_class
),

-- 7. For each drug class, count continued/initiated/discontinued
summary AS (
  SELECT
    drug_class,
    COUNT(*) AS n_stays,
    SUM(CASE WHEN in_first_72h = 1 THEN 1 ELSE 0 END) AS n_first_72h,
    SUM(CASE WHEN in_final_72h = 1 THEN 1 ELSE 0 END) AS n_final_72h,
    SUM(CASE WHEN in_first_72h = 1 AND in_final_72h = 1 THEN 1 ELSE 0 END) AS continued,
    SUM(CASE WHEN in_first_72h = 0 AND in_final_72h = 1 THEN 1 ELSE 0 END) AS initiated,
    SUM(CASE WHEN in_first_72h = 1 AND in_final_72h = 0 THEN 1 ELSE 0 END) AS discontinued
  FROM
    drug_exposure
  GROUP BY
    drug_class
),

-- 8. Total number of ICU stays in cohort
cohort_size AS (
  SELECT COUNT(*) AS n_total FROM cohort
)

-- 9. Final output: percentages and counts
SELECT
  s.drug_class,
  s.n_stays,
  s.n_first_72h,
  s.n_final_72h,
  ROUND(s.n_first_72h / cs.n_total * 100, 1) AS pct_first_72h,
  ROUND(s.n_final_72h / cs.n_total * 100, 1) AS pct_final_72h,
  s.continued,
  s.initiated,
  s.discontinued
FROM
  summary s
CROSS JOIN
  cohort_size cs
ORDER BY
  s.drug_class;