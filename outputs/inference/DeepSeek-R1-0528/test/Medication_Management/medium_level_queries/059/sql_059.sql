WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
cohort_filtered AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime
  FROM cohort c
  WHERE age_at_admit BETWEEN 60 AND 70
  AND EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    WHERE di.subject_id = c.subject_id 
      AND di.hadm_id = c.hadm_id
      AND (
        (di.icd_version = 9 AND di.icd_code LIKE '250%' AND (di.icd_code LIKE '%0' OR di.icd_code LIKE '%2'))
        OR (di.icd_version = 10 AND di.icd_code LIKE 'E11%')
      )
  )
  AND EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    WHERE di.subject_id = c.subject_id 
      AND di.hadm_id = c.hadm_id
      AND (
        (di.icd_version = 9 AND (di.icd_code LIKE '428%' OR di.icd_code LIKE '402%1' OR di.icd_code LIKE '404%1' OR di.icd_code LIKE '404%3'))
        OR (di.icd_version = 10 AND (di.icd_code LIKE 'I50%' OR di.icd_code = 'I11.0' OR di.icd_code = 'I13.0' OR di.icd_code = 'I13.2'))
      )
  )
),
drug_class_mapping AS (
  SELECT 'Antidiabetic' AS drug_class, '%insulin%' AS pattern
  UNION ALL SELECT 'Antidiabetic', '%metformin%'
  UNION ALL SELECT 'Antidiabetic', '%glipizide%'
  UNION ALL SELECT 'Antidiabetic', '%glyburide%'
  UNION ALL SELECT 'Antidiabetic', '%glimepiride%'
  UNION ALL SELECT 'Antidiabetic', '%pioglitazone%'
  UNION ALL SELECT 'Antidiabetic', '%rosiglitazone%'
  UNION ALL SELECT 'Antidiabetic', '%sitagliptin%'
  UNION ALL SELECT 'Antidiabetic', '%saxagliptin%'
  UNION ALL SELECT 'Antidiabetic', '%linagliptin%'
  UNION ALL SELECT 'Antidiabetic', '%exenatide%'
  UNION ALL SELECT 'Antidiabetic', '%liraglutide%'
  UNION ALL SELECT 'Antidiabetic', '%dulaglutide%'
  UNION ALL SELECT 'Antidiabetic', '%semaglutide%'
  UNION ALL SELECT 'Antidiabetic', '%canagliflozin%'
  UNION ALL SELECT 'Antidiabetic', '%dapagliflozin%'
  UNION ALL SELECT 'Antidiabetic', '%empagliflozin%'
  UNION ALL SELECT 'Beta-blocker', '%metoprolol%'
  UNION ALL SELECT 'Beta-blocker', '%propranolol%'
  UNION ALL SELECT 'Beta-blocker', '%atenolol%'
  UNION ALL SELECT 'Beta-blocker', '%carvedilol%'
  UNION ALL SELECT 'Beta-blocker', '%labetalol%'
  UNION ALL SELECT 'Beta-blocker', '%bisoprolol%'
  UNION ALL SELECT 'Beta-blocker', '%nebivolol%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%enalapril%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%lisinopril%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%ramipril%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%captopril%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%benazepril%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%quinapril%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%perindopril%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%trandolapril%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%fosinopril%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%moexipril%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%candesartan%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%irbesartan%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%losartan%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%telmisartan%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%valsartan%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%olmesartan%'
  UNION ALL SELECT 'ACEi/ARB/ARNI', '%sacubitril%'
  UNION ALL SELECT 'Loop diuretic', '%furosemide%'
  UNION ALL SELECT 'Loop diuretic', '%bumetanide%'
  UNION ALL SELECT 'Loop diuretic', '%torsemide%'
  UNION ALL SELECT 'Loop diuretic', '%ethacrynic acid%'
),
first_admin AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    dcm.drug_class,
    MIN(e.charttime) AS first_admin_time
  FROM cohort_filtered c
  CROSS JOIN drug_class_mapping dcm
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id
    AND c.hadm_id = e.hadm_id
    AND LOWER(e.medication) LIKE LOWER(dcm.pattern)
  GROUP BY c.subject_id, c.hadm_id, dcm.drug_class
),
cohort_windows AS (
  SELECT 
    *,
    DATETIME_ADD(admittime, INTERVAL 48 HOUR) AS first_48h_end,
    DATETIME_SUB(dischtime, INTERVAL 24 HOUR) AS final_24h_start
  FROM cohort_filtered
),
flags AS (
  SELECT 
    f.subject_id,
    f.hadm_id,
    f.drug_class,
    CASE 
      WHEN f.first_admin_time BETWEEN cw.admittime AND cw.first_48h_end THEN 1 
      ELSE 0 
    END AS in_first_48h,
    CASE 
      WHEN f.first_admin_time BETWEEN cw.final_24h_start AND cw.dischtime THEN 1 
      ELSE 0 
    END AS in_final_24h
  FROM first_admin f
  INNER JOIN cohort_windows cw
    ON f.subject_id = cw.subject_id
    AND f.hadm_id = cw.hadm_id
),
total_patients AS (
  SELECT COUNT(*) AS total_n
  FROM cohort_filtered
)
SELECT 
  f.drug_class,
  total_n,
  SUM(f.in_first_48h) AS n_first_48h,
  SUM(f.in_final_24h) AS n_final_24h,
  ROUND(100.0 * SUM(f.in_first_48h) / total_n, 2) AS pct_first_48h,
  ROUND(100.0 * SUM(f.in_final_24h) / total_n, 2) AS pct_final_24h,
  ROUND(
    100.0 * SUM(f.in_first_48h) / total_n - 
    100.0 * SUM(f.in_final_24h) / total_n, 
    2
  ) AS abs_diff_pp
FROM flags f
CROSS JOIN total_patients
GROUP BY f.drug_class, total_n
ORDER BY f.drug_class;