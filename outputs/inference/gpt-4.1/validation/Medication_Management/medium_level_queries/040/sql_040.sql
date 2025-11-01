WITH cohort AS (
  -- Select male patients aged 36-46 at admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
),
dx_diabetes AS (
  -- Admissions with diabetes ICD codes
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  WHERE (
    (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250'))
    OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E0[89]|^E1[0-3]'))
  )
),
dx_hf AS (
  -- Admissions with heart failure ICD codes
  SELECT DISTINCT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  WHERE (
    (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
    OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
  )
),
final_cohort AS (
  -- Admissions with both diabetes and heart failure
  SELECT c.*
  FROM cohort c
  JOIN dx_diabetes d1 ON c.hadm_id = d1.hadm_id
  JOIN dx_hf d2 ON c.hadm_id = d2.hadm_id
),
drug_classes AS (
  -- Drug class mapping (expand as needed)
  SELECT 'antidiabetic' AS drug_class, LOWER(drug_name) AS drug_name FROM UNNEST([
    'insulin', 'metformin', 'glipizide', 'glyburide', 'glimepiride', 'pioglitazone', 'rosiglitazone', 'sitagliptin', 'linagliptin', 'canagliflozin', 'dapagliflozin', 'empagliflozin', 'exenatide', 'liraglutide'
  ]) AS drug_name
  UNION ALL
  SELECT 'cardiac', LOWER(drug_name) FROM UNNEST([
    'metoprolol', 'carvedilol', 'bisoprolol', 'atenolol', 'labetalol', -- beta blockers
    'lisinopril', 'enalapril', 'ramipril', 'captopril', -- ACE inhibitors
    'losartan', 'valsartan', 'candesartan', -- ARBs
    'furosemide', 'bumetanide', 'torsemide', -- loop diuretics
    'spironolactone', 'eplerenone', -- aldosterone antagonists
    'digoxin', 'hydralazine', 'isosorbide dinitrate', 'isosorbide mononitrate'
  ]) AS drug_name
),
presc AS (
  -- Prescriptions for cohort admissions, mapped to drug class
  SELECT
    fc.hadm_id,
    fc.admittime,
    fc.dischtime,
    pr.starttime,
    pr.stoptime,
    LOWER(pr.drug) AS drug,
    dc.drug_class
  FROM final_cohort fc
  JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON fc.hadm_id = pr.hadm_id
  JOIN drug_classes dc
    ON LOWER(pr.drug) LIKE CONCAT('%', dc.drug_name, '%')
),
windowed_exposure AS (
  -- For each admission and drug class, flag exposure in first 48h and last 12h
  SELECT
    hadm_id,
    drug_class,
    MAX(
      CASE
        WHEN DATETIME_DIFF(pr.starttime, admittime, HOUR) BETWEEN 0 AND 48 THEN 1
        WHEN DATETIME_DIFF(pr.stoptime, admittime, HOUR) BETWEEN 0 AND 48 THEN 1
        ELSE 0
      END
    ) AS exposed_first_48h,
    MAX(
      CASE
        WHEN DATETIME_DIFF(dischtime, pr.starttime, HOUR) BETWEEN 0 AND 12 THEN 1
        WHEN DATETIME_DIFF(dischtime, pr.stoptime, HOUR) BETWEEN 0 AND 12 THEN 1
        ELSE 0
      END
    ) AS exposed_last_12h
  FROM presc pr
  GROUP BY hadm_id, drug_class
),
agg AS (
  -- Aggregate prevalence per drug class
  SELECT
    drug_class,
    COUNT(DISTINCT hadm_id) AS n_admissions,
    SUM(exposed_first_48h) AS n_exposed_first_48h,
    SUM(exposed_last_12h) AS n_exposed_last_12h
  FROM windowed_exposure
  GROUP BY drug_class
),
final AS (
  SELECT
    drug_class,
    ROUND(100.0 * n_exposed_first_48h / n_admissions, 1) AS prevalence_first_48h_pct,
    ROUND(100.0 * n_exposed_last_12h / n_admissions, 1) AS prevalence_last_12h_pct,
    ROUND(100.0 * (n_exposed_last_12h - n_exposed_first_48h) / n_admissions, 1) AS absolute_difference_pp
  FROM agg
)
SELECT * FROM final
ORDER BY drug_class;