WITH 
cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 37 AND 47
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 144
),
diabetes_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E09%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%'))
    OR (icd_version = 9 AND (icd_code LIKE '249%' OR icd_code LIKE '250%'))
),
hf_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND icd_code LIKE 'I50%')
    OR (icd_version = 9 AND icd_code LIKE '428%')
),
cohort_final AS (
  SELECT c.hadm_id, c.admittime, c.dischtime
  FROM cohort c
  INNER JOIN diabetes_adm d ON c.hadm_id = d.hadm_id
  INNER JOIN hf_adm h ON c.hadm_id = h.hadm_id
),
cohort_windows AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    admittime AS window1_start,
    TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) AS window1_end,
    TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR) AS window2_start,
    dischtime AS window2_end
  FROM cohort_final
),
pres_drug_classes AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    p.stoptime,
    -- Antidiabetics
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%glipizide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%glyburide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%saxagliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%linagliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%alogliptin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%dapagliflozin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%ertugliflozin%' THEN 1
      WHEN LOWER(p.drug) LIKE '%liraglutide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%semaglutide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%exenatide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%dulaglutide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' THEN 1
      WHEN LOWER(p.drug) LIKE '%rosiglitazone%' THEN 1
      WHEN LOWER(p.drug) LIKE '%acarbose%' THEN 1
      WHEN LOWER(p.drug) LIKE '%miglitol%' THEN 1
      WHEN LOWER(p.drug) LIKE '%repaglinide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%nateglinide%' THEN 1
      ELSE 0 
    END AS is_antidiabetic,
    -- Beta-blockers
    CASE 
      WHEN LOWER(p.drug) LIKE '%metoprolol%' THEN 1
      WHEN LOWER(p.drug) LIKE '%atenolol%' THEN 1
      WHEN LOWER(p.drug) LIKE '%carvedilol%' THEN 1
      WHEN LOWER(p.drug) LIKE '%bisoprolol%' THEN 1
      WHEN LOWER(p.drug) LIKE '%propranolol%' THEN 1
      WHEN LOWER(p.drug) LIKE '%nadolol%' THEN 1
      WHEN LOWER(p.drug) LIKE '%sotalol%' THEN 1
      WHEN LOWER(p.drug) LIKE '%timolol%' THEN 1
      WHEN LOWER(p.drug) LIKE '%labetalol%' THEN 1
      ELSE 0 
    END AS is_beta_blocker,
    -- ACEi/ARB/ARNI
    CASE 
      WHEN LOWER(p.drug) LIKE '%lisinopril%' THEN 1
      WHEN LOWER(p.drug) LIKE '%enalapril%' THEN 1
      WHEN LOWER(p.drug) LIKE '%ramipril%' THEN 1
      WHEN LOWER(p.drug) LIKE '%captopril%' THEN 1
      WHEN LOWER(p.drug) LIKE '%benazepril%' THEN 1
      WHEN LOWER(p.drug) LIKE '%fosinopril%' THEN 1
      WHEN LOWER(p.drug) LIKE '%moexipril%' THEN 1
      WHEN LOWER(p.drug) LIKE '%perindopril%' THEN 1
      WHEN LOWER(p.drug) LIKE '%quinapril%' THEN 1
      WHEN LOWER(p.drug) LIKE '%trandolapril%' THEN 1
      WHEN LOWER(p.drug) LIKE '%losartan%' THEN 1
      WHEN LOWER(p.drug) LIKE '%valsartan%' THEN 1
      WHEN LOWER(p.drug) LIKE '%irbesartan%' THEN 1
      WHEN LOWER(p.drug) LIKE '%candesartan%' THEN 1
      WHEN LOWER(p.drug) LIKE '%telmisartan%' THEN 1
      WHEN LOWER(p.drug) LIKE '%olmesartan%' THEN 1
      WHEN LOWER(p.drug) LIKE '%azilsartan%' THEN 1
      WHEN (LOWER(p.drug) LIKE '%sacubitril%' AND LOWER(p.drug) LIKE '%valsartan%') THEN 1
      ELSE 0 
    END AS is_acei_arb_arni,
    -- Loop diuretics
    CASE 
      WHEN LOWER(p.drug) LIKE '%furosemide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%lasix%' THEN 1
      WHEN LOWER(p.drug) LIKE '%bumetanide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%torsemide%' THEN 1
      WHEN LOWER(p.drug) LIKE '%ethacrynic acid%' THEN 1
      ELSE 0 
    END AS is_loop_diuretic
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort_final c 
    ON p.hadm_id = c.hadm_id
),
adm_drug_status AS (
  SELECT 
    cw.hadm_id,
    MAX(CASE WHEN p.is_antidiabetic = 1 
              AND p.starttime < cw.window1_end 
              AND COALESCE(p.stoptime, cw.dischtime) > cw.window1_start 
             THEN 1 ELSE 0 END) AS antidiabetic_window1,
    MAX(CASE WHEN p.is_antidiabetic = 1 
              AND p.starttime < cw.window2_end 
              AND COALESCE(p.stoptime, cw.dischtime) > cw.window2_start 
             THEN 1 ELSE 0 END) AS antidiabetic_window2,
    MAX(CASE WHEN p.is_beta_blocker = 1 
              AND p.starttime < cw.window1_end 
              AND COALESCE(p.stoptime, cw.dischtime) > cw.window1_start 
             THEN 1 ELSE 0 END) AS beta_blocker_window1,
    MAX(CASE WHEN p.is_beta_blocker = 1 
              AND p.starttime < cw.window2_end 
              AND COALESCE(p.stoptime, cw.dischtime) > cw.window2_start 
             THEN 1 ELSE 0 END) AS beta_blocker_window2,
    MAX(CASE WHEN p.is_acei_arb_arni = 1 
              AND p.starttime < cw.window1_end 
              AND COALESCE(p.stoptime, cw.dischtime) > cw.window1_start 
             THEN 1 ELSE 0 END) AS acei_arb_arni_window1,
    MAX(CASE WHEN p.is_acei_arb_arni = 1 
              AND p.starttime < cw.window2_end 
              AND COALESCE(p.stoptime, cw.dischtime) > cw.window2_start 
             THEN 1 ELSE 0 END) AS acei_arb_arni_window2,
    MAX(CASE WHEN p.is_loop_diuretic = 1 
              AND p.starttime < cw.window1_end 
              AND COALESCE(p.stoptime, cw.dischtime) > cw.window1_start 
             THEN 1 ELSE 0 END) AS loop_diuretic_window1,
    MAX(CASE WHEN p.is_loop_diuretic = 1 
              AND p.starttime < cw.window2_end 
              AND COALESCE(p.stoptime, cw.dischtime) > cw.window2_start 
             THEN 1 ELSE 0 END) AS loop_diuretic_window2
  FROM cohort_windows cw
  LEFT JOIN pres_drug_classes p 
    ON cw.hadm_id = p.hadm_id
  GROUP BY cw.hadm_id
)
SELECT 
  'antidiabetic' AS drug_class,
  ROUND(SUM(antidiabetic_window1) * 100.0 / COUNT(*), 1) AS pct_window1,
  ROUND(SUM(antidiabetic_window2) * 100.0 / COUNT(*), 1) AS pct_window2,
  SUM(CASE WHEN antidiabetic_window1 = 1 AND antidiabetic_window2 = 1 THEN 1 ELSE 0 END) AS continued_count,
  SUM(CASE WHEN antidiabetic_window1 = 0 AND antidiabetic_window2 = 1 THEN 1 ELSE 0 END) AS initiated_count,
  SUM(CASE WHEN antidiabetic_window1 = 1 AND antidiabetic_window2 = 0 THEN 1 ELSE 0 END) AS discontinued_count
FROM adm_drug_status
UNION ALL
SELECT 
  'beta_blocker',
  ROUND(SUM(beta_blocker_window1) * 100.0 / COUNT(*), 1),
  ROUND(SUM(beta_blocker_window2) * 100.0 / COUNT(*), 1),
  SUM(CASE WHEN beta_blocker_window1 = 1 AND beta_blocker_window2 = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN beta_blocker_window1 = 0 AND beta_blocker_window2 = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN beta_blocker_window1 = 1 AND beta_blocker_window2 = 0 THEN 1 ELSE 0 END)
FROM adm_drug_status
UNION ALL
SELECT 
  'acei_arb_arni',
  ROUND(SUM(acei_arb_arni_window1) * 100.0 / COUNT(*), 1),
  ROUND(SUM(acei_arb_arni_window2) * 100.0 / COUNT(*), 1),
  SUM(CASE WHEN acei_arb_arni_window1 = 1 AND acei_arb_arni_window2 = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN acei_arb_arni_window1 = 0 AND acei_arb_arni_window2 = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN acei_arb_arni_window1 = 1 AND acei_arb_arni_window2 = 0 THEN 1 ELSE 0 END)
FROM adm_drug_status
UNION ALL
SELECT 
  'loop_diuretic',
  ROUND(SUM(loop_diuretic_window1) * 100.0 / COUNT(*), 1),
  ROUND(SUM(loop_diuretic_window2) * 100.0 / COUNT(*), 1),
  SUM(CASE WHEN loop_diuretic_window1 = 1 AND loop_diuretic_window2 = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN loop_diuretic_window1 = 0 AND loop_diuretic_window2 = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN loop_diuretic_window1 = 1 AND loop_diuretic_window2 = 0 THEN 1 ELSE 0 END)
FROM adm_drug_status;