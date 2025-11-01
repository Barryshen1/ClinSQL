WITH
-- 1. Identify female patients aged 67-77
cohort_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 67 AND 77
),

-- 2. Admissions for these patients
cohort_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cohort_patients p ON a.subject_id = p.subject_id
),

-- 3. Admissions with T2DM and HF
dx_t2dm AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250[.]([0-9]|[0-9][0-9])$') AND NOT REGEXP_CONTAINS(d.icd_code, r'^250[.]1')) -- T2DM ICD-9
    OR
    (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E11')) -- T2DM ICD-10
  )
),
dx_hf AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE (
    (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428')) -- HF ICD-9
    OR
    (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50')) -- HF ICD-10
  )
),
cohort_final AS (
  SELECT ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime
  FROM cohort_admissions ca
  JOIN dx_t2dm t2 ON ca.hadm_id = t2.hadm_id
  JOIN dx_hf hf ON ca.hadm_id = hf.hadm_id
),

-- 4. Drug class mapping
drug_class_map AS (
  SELECT 'insulin' AS drug_class, r'(?i)insulin' AS pattern UNION ALL
  SELECT 'metformin', r'(?i)metformin' UNION ALL
  SELECT 'SU', r'(?i)glipizide|glyburide|glimepiride' UNION ALL
  SELECT 'DPP-4', r'(?i)sitagliptin|linagliptin|saxagliptin|alogliptin' UNION ALL
  SELECT 'SGLT2', r'(?i)canagliflozin|dapagliflozin|empagliflozin|ertugliflozin' UNION ALL
  SELECT 'GLP-1', r'(?i)liraglutide|exenatide|dulaglutide|semaglutide' UNION ALL
  SELECT 'TZD', r'(?i)pioglitazone|rosiglitazone'
),

-- 5. All drug orders for cohort admissions (prescriptions and pharmacy)
all_drug_orders AS (
  SELECT
    p.subject_id, p.hadm_id, p.starttime AS drug_time, LOWER(p.drug) AS drug_name
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort_final c ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  WHERE p.starttime IS NOT NULL

  UNION ALL

  SELECT
    ph.subject_id, ph.hadm_id, ph.starttime AS drug_time, LOWER(ph.medication) AS drug_name
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  JOIN cohort_final c ON ph.subject_id = c.subject_id AND ph.hadm_id = c.hadm_id
  WHERE ph.starttime IS NOT NULL
),

-- 6. Map drugs to classes and filter to initiations during admission
drug_initiations AS (
  SELECT
    ado.subject_id,
    ado.hadm_id,
    c.admittime,
    c.dischtime,
    dc.drug_class,
    ado.drug_time
  FROM all_drug_orders ado
  JOIN cohort_final c ON ado.subject_id = c.subject_id AND ado.hadm_id = c.hadm_id
  JOIN drug_class_map dc ON REGEXP_CONTAINS(ado.drug_name, dc.pattern)
  WHERE ado.drug_time >= c.admittime AND ado.drug_time <= c.dischtime
),

-- 7. For each admission and drug class, get first initiation time
first_initiation AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    drug_class,
    MIN(drug_time) AS first_drug_time
  FROM drug_initiations
  GROUP BY subject_id, hadm_id, admittime, dischtime, drug_class
),

-- 8. For each admission, flag initiation in first 12h and final 48h
initiation_flags AS (
  SELECT
    fi.subject_id,
    fi.hadm_id,
    fi.drug_class,
    -- First 12h window
    CASE
      WHEN TIMESTAMP_DIFF(fi.first_drug_time, fi.admittime, MINUTE) < 12*60 THEN 1 ELSE 0
    END AS initiated_first_12h,
    -- Final 48h window
    CASE
      WHEN TIMESTAMP_DIFF(fi.dischtime, fi.first_drug_time, MINUTE) < 48*60 THEN 1 ELSE 0
    END AS initiated_final_48h
  FROM first_initiation fi
),

-- 9. For each admission and drug class, collapse flags (if multiple initiations, only first counts)
admission_class_flags AS (
  SELECT
    subject_id,
    hadm_id,
    drug_class,
    MAX(initiated_first_12h) AS initiated_first_12h,
    MAX(initiated_final_48h) AS initiated_final_48h
  FROM initiation_flags
  GROUP BY subject_id, hadm_id, drug_class
),

-- 10. For denominator: total admissions in cohort
total_admissions AS (
  SELECT COUNT(DISTINCT hadm_id) AS n_admissions FROM cohort_final
),

-- 11. For each drug class, calculate % initiated in first 12h and final 48h
class_stats AS (
  SELECT
    drug_class,
    COUNTIF(initiated_first_12h = 1) AS n_first_12h,
    COUNTIF(initiated_final_48h = 1) AS n_final_48h
  FROM admission_class_flags
  GROUP BY drug_class
),

-- 12. Final output: calculate percentages and net change
final_output AS (
  SELECT
    cs.drug_class,
    ROUND(100.0 * cs.n_first_12h / ta.n_admissions, 2) AS pct_first_12h,
    ROUND(100.0 * cs.n_final_48h / ta.n_admissions, 2) AS pct_final_48h,
    ROUND(100.0 * (cs.n_final_48h - cs.n_first_12h) / ta.n_admissions, 2) AS net_change_pp
  FROM class_stats cs
  CROSS JOIN total_admissions ta
)

SELECT * FROM final_output
ORDER BY drug_class;