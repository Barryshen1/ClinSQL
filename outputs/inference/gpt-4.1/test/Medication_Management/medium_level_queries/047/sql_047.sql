WITH
-- 1. Get male patients age 40-50
cohort_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 40 AND 50
),

-- 2. Get admissions with diabetes AND heart failure
cohort_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN cohort_patients p ON a.subject_id = p.subject_id
  -- Diabetes ICD codes
  JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250'))
      OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E0[89]|^E1[0-3]'))
    GROUP BY hadm_id
  ) d ON a.hadm_id = d.hadm_id
  -- Heart Failure ICD codes
  JOIN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428'))
      OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
    GROUP BY hadm_id
  ) hf ON a.hadm_id = hf.hadm_id
),

-- 3. Medication class definitions (lists of drug names)
med_classes AS (
  SELECT 'antidiabetic' AS class, drug_name FROM UNNEST([
    'metformin', 'insulin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'linagliptin', 'empagliflozin', 'canagliflozin', 'dapagliflozin', 'liraglutide', 'exenatide', 'pioglitazone', 'rosiglitazone'
  ]) AS drug_name
  UNION ALL
  SELECT 'beta_blocker', drug_name FROM UNNEST([
    'metoprolol', 'carvedilol', 'bisoprolol', 'atenolol', 'propranolol', 'labetalol'
  ]) AS drug_name
  UNION ALL
  SELECT 'ace_arb_arni', drug_name FROM UNNEST([
    'lisinopril', 'enalapril', 'ramipril', 'captopril', 'benazepril', 'losartan', 'valsartan', 'candesartan', 'irbesartan', 'olmesartan', 'sacubitril/valsartan'
  ]) AS drug_name
  UNION ALL
  SELECT 'loop_diuretic', drug_name FROM UNNEST([
    'furosemide', 'bumetanide', 'torsemide'
  ]) AS drug_name
),

-- 4. For each admission, get medication administrations by class
adm_medications AS (
  SELECT
    ca.subject_id,
    ca.hadm_id,
    ca.admittime,
    ca.dischtime,
    mc.class,
    MIN(p.starttime) AS first_starttime,
    MAX(p.stoptime) AS last_stoptime,
    -- For each drug, get all administrations
    ARRAY_AGG(
      STRUCT(
        p.starttime AS starttime,
        p.stoptime AS stoptime
      )
    ) AS admin_times
  FROM cohort_admissions ca
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON ca.subject_id = p.subject_id AND ca.hadm_id = p.hadm_id
  JOIN med_classes mc
    ON LOWER(p.drug) LIKE CONCAT('%', LOWER(mc.drug_name), '%')
  GROUP BY ca.subject_id, ca.hadm_id, ca.admittime, ca.dischtime, mc.class
),

-- 5. For each admission and class, determine status in first/last 24h
adm_med_status AS (
  SELECT
    subject_id,
    hadm_id,
    class,
    -- Any administration in first 24h
    COUNTIF(
      (
        admin.starttime <= admittime + INTERVAL 24 HOUR
        AND (admin.stoptime IS NULL OR admin.stoptime >= admittime)
      )
      OR
      (
        admin.starttime >= admittime
        AND admin.starttime <= admittime + INTERVAL 24 HOUR
      )
    ) > 0 AS in_first_24h,
    -- Any administration in last 24h
    COUNTIF(
      (
        admin.starttime <= dischtime
        AND (admin.stoptime IS NULL OR admin.stoptime >= dischtime - INTERVAL 24 HOUR)
      )
      OR
      (
        admin.starttime >= dischtime - INTERVAL 24 HOUR
        AND admin.starttime <= dischtime
      )
    ) > 0 AS in_last_24h
  FROM adm_medications,
    UNNEST(admin_times) AS admin
  GROUP BY subject_id, hadm_id, class
),

-- 6. For each admission/class, assign status
adm_med_status_final AS (
  SELECT
    subject_id,
    hadm_id,
    class,
    in_first_24h,
    in_last_24h,
    CASE
      WHEN in_first_24h AND in_last_24h THEN 'continued'
      WHEN NOT in_first_24h AND in_last_24h THEN 'initiated_late'
      WHEN in_first_24h AND NOT in_last_24h THEN 'discontinued'
      ELSE 'none'
    END AS status
  FROM adm_med_status
),

-- 7. Aggregate counts and percentages
class_stats AS (
  SELECT
    class,
    COUNT(DISTINCT hadm_id) AS n_admissions,
    COUNTIF(in_first_24h) AS n_first_24h,
    COUNTIF(in_last_24h) AS n_last_24h,
    COUNTIF(status = 'continued') AS n_continued,
    COUNTIF(status = 'initiated_late') AS n_initiated_late,
    COUNTIF(status = 'discontinued') AS n_discontinued,
    SAFE_DIVIDE(COUNTIF(in_first_24h), COUNT(DISTINCT hadm_id)) * 100 AS pct_first_24h,
    SAFE_DIVIDE(COUNTIF(in_last_24h), COUNT(DISTINCT hadm_id)) * 100 AS pct_last_24h
  FROM adm_med_status_final
  GROUP BY class
)

SELECT
  class,
  n_admissions,
  pct_first_24h,
  pct_last_24h,
  n_continued,
  n_initiated_late,
  n_discontinued
FROM class_stats
ORDER BY class;