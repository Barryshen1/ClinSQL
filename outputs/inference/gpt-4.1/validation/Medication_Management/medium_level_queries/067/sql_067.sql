WITH cohort AS (
  -- Select male patients aged 64-74 at admission
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
    AND pat.anchor_age BETWEEN 64 AND 74
),
diabetes_adm AS (
  -- Admissions with diabetes diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  WHERE
    (
      (diag.icd_version = 9 AND diag.icd_code LIKE '250%')
      OR
      (diag.icd_version = 10 AND diag.icd_code LIKE 'E1%')
    )
),
acute_hf_adm AS (
  -- Admissions with acute heart failure diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
  WHERE
    (
      (diag.icd_version = 9 AND diag.icd_code IN (
        '4280','4281','42820','42821','42822','42823',
        '42830','42831','42832','42833','42840','42841','42842','42843'
      ))
      OR
      (diag.icd_version = 10 AND diag.icd_code IN (
        'I5021','I5023','I5031','I5033','I5041','I5043',
        'I50811','I50813','I50821','I50823','I5084','I509'
      ))
    )
),
final_cohort AS (
  -- Admissions with both diabetes and acute HF
  SELECT c.*
  FROM cohort c
    JOIN diabetes_adm d ON c.hadm_id = d.hadm_id
    JOIN acute_hf_adm h ON c.hadm_id = h.hadm_id
),
drug_classes AS (
  -- Map drug names to antidiabetic classes
  SELECT 'insulin' AS drug_class, 'insulin' AS drug_pattern UNION ALL
  SELECT 'metformin', 'metformin' UNION ALL
  SELECT 'sulfonylureas', 'glipizide' UNION ALL
  SELECT 'sulfonylureas', 'glimepiride' UNION ALL
  SELECT 'sulfonylureas', 'glyburide' UNION ALL
  SELECT 'dpp4', 'sitagliptin' UNION ALL
  SELECT 'dpp4', 'linagliptin' UNION ALL
  SELECT 'dpp4', 'alogliptin' UNION ALL
  SELECT 'dpp4', 'saxagliptin' UNION ALL
  SELECT 'sglt2', 'empagliflozin' UNION ALL
  SELECT 'sglt2', 'canagliflozin' UNION ALL
  SELECT 'sglt2', 'dapagliflozin' UNION ALL
  SELECT 'glp1', 'liraglutide' UNION ALL
  SELECT 'glp1', 'semaglutide' UNION ALL
  SELECT 'glp1', 'exenatide' UNION ALL
  SELECT 'glp1', 'dulaglutide' UNION ALL
  SELECT 'glp1', 'albiglutide' UNION ALL
  SELECT 'tzds', 'pioglitazone' UNION ALL
  SELECT 'tzds', 'rosiglitazone'
),
drug_initiation AS (
  -- For each admission, find first starttime for each drug class
  SELECT
    fc.subject_id,
    fc.hadm_id,
    fc.admittime,
    fc.dischtime,
    dc.drug_class,
    MIN(pr.starttime) AS first_starttime
  FROM final_cohort fc
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON fc.hadm_id = pr.hadm_id
    JOIN drug_classes dc
      ON LOWER(pr.drug) LIKE CONCAT('%', dc.drug_pattern, '%')
  GROUP BY fc.subject_id, fc.hadm_id, fc.admittime, fc.dischtime, dc.drug_class
),
window_flags AS (
  -- Flag initiations in first 12h and final 48h
  SELECT
    di.subject_id,
    di.hadm_id,
    di.drug_class,
    di.first_starttime,
    CASE WHEN TIMESTAMP_DIFF(di.first_starttime, di.admittime, HOUR) BETWEEN 0 AND 12 THEN 1 ELSE 0 END AS in_first_12h,
    CASE WHEN TIMESTAMP_DIFF(di.dischtime, di.first_starttime, HOUR) BETWEEN 0 AND 48 THEN 1 ELSE 0 END AS in_final_48h
  FROM drug_initiation di
)
-- Calculate percentages by drug class and window
SELECT
  dc.drug_class,
  COUNT(DISTINCT CASE WHEN wf.in_first_12h = 1 THEN wf.hadm_id END) AS n_first_12h,
  COUNT(DISTINCT CASE WHEN wf.in_final_48h = 1 THEN wf.hadm_id END) AS n_final_48h,
  cohort_size.cohort_n,
  ROUND(COUNT(DISTINCT CASE WHEN wf.in_first_12h = 1 THEN wf.hadm_id END) * 100.0 / cohort_size.cohort_n, 1) AS pct_first_12h,
  ROUND(COUNT(DISTINCT CASE WHEN wf.in_final_48h = 1 THEN wf.hadm_id END) * 100.0 / cohort_size.cohort_n, 1) AS pct_final_48h
FROM drug_classes dc
LEFT JOIN window_flags wf ON dc.drug_class = wf.drug_class
CROSS JOIN (
  SELECT COUNT(DISTINCT hadm_id) AS cohort_n FROM final_cohort
) cohort_size
GROUP BY dc.drug_class, cohort_size.cohort_n
ORDER BY dc.drug_class;