WITH cohort AS (
  -- Select male patients aged 77-87 at admission
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 77 AND 87
),
diagnoses AS (
  -- Get admissions with diabetes and heart failure
  SELECT
    hadm_id,
    MAX(CASE WHEN
      (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250')) OR
      (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E0[89]|^E1[0-3]'))
      THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN
      (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428')) OR
      (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
      THEN 1 ELSE 0 END) AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    hadm_id
),
eligible_admissions AS (
  -- Admissions with both diabetes and heart failure
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM
    cohort c
    JOIN diagnoses d ON c.hadm_id = d.hadm_id
  WHERE
    d.has_diabetes = 1 AND d.has_hf = 1
),
drug_classes AS (
  -- Drug class definitions (lowercase for matching)
  SELECT 'antidiabetic' AS drug_class, 'insulin' AS drug_name UNION ALL
  SELECT 'antidiabetic', 'metformin' UNION ALL
  SELECT 'antidiabetic', 'glipizide' UNION ALL
  SELECT 'antidiabetic', 'glyburide' UNION ALL
  SELECT 'antidiabetic', 'glimepiride' UNION ALL
  SELECT 'antidiabetic', 'pioglitazone' UNION ALL
  SELECT 'antidiabetic', 'sitagliptin' UNION ALL
  SELECT 'antidiabetic', 'empagliflozin' UNION ALL
  SELECT 'antidiabetic', 'canagliflozin' UNION ALL
  SELECT 'antidiabetic', 'dapagliflozin' UNION ALL
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
first_prescription AS (
  -- For each admission and drug class, get first prescription starttime
  SELECT
    ea.subject_id,
    ea.hadm_id,
    dc.drug_class,
    MIN(p.starttime) AS first_starttime
  FROM
    eligible_admissions ea
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON ea.hadm_id = p.hadm_id
    JOIN drug_classes dc
      ON LOWER(p.drug) LIKE CONCAT('%', dc.drug_name, '%')
  WHERE
    p.starttime >= ea.admittime -- Only new starts after admission
  GROUP BY
    ea.subject_id, ea.hadm_id, dc.drug_class
),
initiation_flags AS (
  -- Flag initiations in first 48h and last 12h
  SELECT
    ea.subject_id,
    ea.hadm_id,
    dc.drug_class,
    fp.first_starttime,
    ea.admittime,
    ea.dischtime,
    CASE WHEN fp.first_starttime IS NOT NULL
      AND TIMESTAMP_DIFF(fp.first_starttime, ea.admittime, HOUR) < 48
      THEN 1 ELSE 0 END AS initiated_48h,
    CASE WHEN fp.first_starttime IS NOT NULL
      AND TIMESTAMP_DIFF(ea.dischtime, fp.first_starttime, HOUR) <= 12
      THEN 1 ELSE 0 END AS initiated_last12h
  FROM
    eligible_admissions ea
    CROSS JOIN (SELECT DISTINCT drug_class FROM drug_classes) dc
    LEFT JOIN first_prescription fp
      ON ea.subject_id = fp.subject_id
      AND ea.hadm_id = fp.hadm_id
      AND dc.drug_class = fp.drug_class
)
SELECT
  drug_class,
  ROUND(SUM(initiated_48h) / COUNT(*) * 100, 1) AS pct_initiated_48h,
  ROUND(SUM(initiated_last12h) / COUNT(*) * 100, 1) AS pct_initiated_last12h,
  ROUND(SUM(initiated_last12h) / COUNT(*) * 100, 1) - ROUND(SUM(initiated_48h) / COUNT(*) * 100, 1) AS net_change_pct
FROM
  initiation_flags
GROUP BY
  drug_class
ORDER BY
  drug_class;