WITH dm_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND (icd_code LIKE 'E08%' OR icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' 
         OR icd_code LIKE 'E12%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%')
),
hf_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND icd_code LIKE 'I50%'
),
cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN dm_hadms dm ON a.hadm_id = dm.hadm_id
  JOIN hf_hadms hf ON a.hadm_id = hf.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
),
drug_classes AS (
  -- Antidiabetic
  SELECT 'antidiabetic' AS class, '%METFORMIN%' AS pattern UNION ALL
  SELECT 'antidiabetic', '%INSULIN%' UNION ALL
  SELECT 'antidiabetic', '%GLIPIZIDE%' UNION ALL
  SELECT 'antidiabetic', '%GLYBURIDE%' UNION ALL
  SELECT 'antidiabetic', '%GLIMEPIRIDE%' UNION ALL
  SELECT 'antidiabetic', '%PIOGLITAZONE%' UNION ALL
  SELECT 'antidiabetic', '%SITAGLIPTIN%' UNION ALL
  SELECT 'antidiabetic', '%EMPAGLIFLOZIN%' UNION ALL
  -- Beta-blocker
  SELECT 'beta_blocker', '%METOPROLOL%' UNION ALL
  SELECT 'beta_blocker', '%ATENOLOL%' UNION ALL
  SELECT 'beta_blocker', '%CARVEDILOL%' UNION ALL
  SELECT 'beta_blocker', '%BISOPROLOL%' UNION ALL
  SELECT 'beta_blocker', '%PROPRANOLOL%' UNION ALL
  SELECT 'beta_blocker', '%LABETALOL%' UNION ALL
  SELECT 'beta_blocker', '%NEBIVOLOL%' UNION ALL
  -- ACEi/ARB/ARNI
  SELECT 'acei_arb_arni', '%LISINOPRIL%' UNION ALL
  SELECT 'acei_arb_arni', '%ENALAPRIL%' UNION ALL
  SELECT 'acei_arb_arni', '%RAMIPRIL%' UNION ALL
  SELECT 'acei_arb_arni', '%CAPTOPRIL%' UNION ALL
  SELECT 'acei_arb_arni', '%LOSARTAN%' UNION ALL
  SELECT 'acei_arb_arni', '%VALSARTAN%' UNION ALL
  SELECT 'acei_arb_arni', '%IRBESARTAN%' UNION ALL
  SELECT 'acei_arb_arni', '%CANDESARTAN%' UNION ALL
  SELECT 'acei_arb_arni', '%TELMISARTAN%' UNION ALL
  SELECT 'acei_arb_arni', '%SACUBITRIL%' UNION ALL
  -- Loop diuretic
  SELECT 'loop_diuretic', '%FUROSEMIDE%' UNION ALL
  SELECT 'loop_diuretic', '%BUMETANIDE%' UNION ALL
  SELECT 'loop_diuretic', '%TORSEMIDE%'
),
prescriptions_class AS (
  SELECT p.subject_id, p.hadm_id, dc.class, p.starttime, p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN drug_classes dc ON p.drug LIKE dc.pattern
  JOIN cohort c ON p.hadm_id = c.hadm_id
),
med_flags AS (
  SELECT 
    c.hadm_id,
    dc.class,
    COALESCE(
      MAX(CASE 
        WHEN pc.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY) 
             AND (pc.stoptime IS NULL OR pc.stoptime >= c.admittime)
        THEN 1 
        ELSE 0 
      END), 0
    ) AS on_first,
    COALESCE(
      MAX(CASE 
        WHEN pc.starttime <= c.dischtime 
             AND (pc.stoptime IS NULL OR pc.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 1 DAY))
        THEN 1 
        ELSE 0 
      END), 0
    ) AS on_last
  FROM cohort c
  CROSS JOIN (
    SELECT DISTINCT class FROM drug_classes
  ) dc
  LEFT JOIN prescriptions_class pc 
    ON pc.hadm_id = c.hadm_id AND pc.class = dc.class
  GROUP BY c.hadm_id, dc.class
)
SELECT 
  class,
  ROUND(AVG(on_first) * 100, 2) AS pct_on_first_24h,
  ROUND(AVG(on_last) * 100, 2) AS pct_on_last_24h,
  COUNT(*) AS total_patients,
  SUM(CASE WHEN on_first = 1 AND on_last = 1 THEN 1 ELSE 0 END) AS count_continued,
  SUM(CASE WHEN on_first = 0 AND on_last = 1 THEN 1 ELSE 0 END) AS count_initiated_late,
  SUM(CASE WHEN on_first = 1 AND on_last = 0 THEN 1 ELSE 0 END) AS count_discontinued,
  SUM(CASE WHEN on_first = 0 AND on_last = 0 THEN 1 ELSE 0 END) AS count_none
FROM med_flags
GROUP BY class
ORDER BY 
  CASE class
    WHEN 'antidiabetic' THEN 1
    WHEN 'beta_blocker' THEN 2
    WHEN 'acei_arb_arni' THEN 3
    WHEN 'loop_diuretic' THEN 4
  END;