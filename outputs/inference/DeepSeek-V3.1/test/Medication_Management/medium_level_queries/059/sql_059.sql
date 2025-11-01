WITH cohort AS (
  -- Get females aged 60-70 with T2DM and HF
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 60 AND 70
    AND adm.hadm_id IN (
      -- T2DM
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (
        (icd_version = 10 AND icd_code LIKE 'E11%') OR
        (icd_version = 9 AND icd_code LIKE '250%' AND (icd_code LIKE '%0' OR icd_code LIKE '%2'))
      )
      INTERSECT DISTINCT
      -- HF
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (
        (icd_version = 10 AND icd_code LIKE 'I50%') OR
        (icd_version = 9 AND icd_code LIKE '428%')
      )
    )
),

-- Define medication classes with regex patterns
med_classes AS (
  SELECT
    'antidiabetic' AS class,
    r'(?i)(metformin|insulin|glipizide|glyburide|glimepiride|sitagliptin|saxagliptin|linagliptin|alogliptin|dapagliflozin|empagliflozin|canagliflozin|pioglitazone|rosiglitazone|nateglinide|repaglinide|acarbose|miglitol|exenatide|liraglutide|dulaglutide|lixisenatide|semaglutide)' AS pattern
  UNION ALL SELECT
    'beta_blocker',
    r'(?i)(metoprolol|atenolol|propranolol|carvedilol|labetalol|bisoprolol|nebivolol|acebutolol|pindolol|timolol)'
  UNION ALL SELECT
    'acei_arb_arni',
    r'(?i)(lisinopril|enalapril|ramipril|quinapril|perindopril|captopril|benazepril|trandolapril|fosinopril|losartan|valsartan|irbesartan|candesartan|olmesartan|telmisartan|azilsartan|eprosartan|sacubitril)'
  UNION ALL SELECT
    'loop_diuretic',
    r'(?i)(furosemide|bumetanide|torsemide|ethacrynic acid)'
),

-- Get first initiation time for each drug class per admission
first_rx AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    mc.class,
    MIN(p.starttime) AS first_start
  FROM cohort c
  CROSS JOIN med_classes mc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE REGEXP_CONTAINS(p.drug, mc.pattern)
  GROUP BY c.subject_id, c.hadm_id, mc.class
),

-- Flag initiations in first 48h or final 24h
flagged_rx AS (
  SELECT
    fr.subject_id,
    fr.hadm_id,
    fr.class,
    CASE
      WHEN fr.first_start BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1
      ELSE 0
    END AS init_first_48h,
    CASE
      WHEN fr.first_start BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime THEN 1
      ELSE 0
    END AS init_final_24h
  FROM first_rx fr
  INNER JOIN cohort c
    ON fr.hadm_id = c.hadm_id
),

-- Aggregate per class
aggregated AS (
  SELECT
    class,
    COUNT(DISTINCT hadm_id) AS total_admissions,
    SUM(init_first_48h) AS count_first_48h,
    SUM(init_final_24h) AS count_final_24h,
    ROUND(100.0 * SUM(init_first_48h) / COUNT(DISTINCT hadm_id), 1) AS pct_first_48h,
    ROUND(100.0 * SUM(init_final_24h) / COUNT(DISTINCT hadm_id), 1) AS pct_final_24h,
    ROUND(100.0 * SUM(init_first_48h) / COUNT(DISTINCT hadm_id) - 100.0 * SUM(init_final_24h) / COUNT(DISTINCT hadm_id), 1) AS abs_diff_pp
  FROM flagged_rx
  GROUP BY class
)

-- Final output
SELECT
  class,
  total_admissions,
  count_first_48h,
  count_final_24h,
  pct_first_48h,
  pct_final_24h,
  abs_diff_pp
FROM aggregated
ORDER BY class;