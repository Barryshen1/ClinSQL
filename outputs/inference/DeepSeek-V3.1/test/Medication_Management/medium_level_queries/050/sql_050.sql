WITH cohort AS (
  -- Get admissions for males aged 49-59 with T2DM and HF
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (
        (icd_code LIKE 'E11%' AND icd_version = 10) OR 
        (icd_code LIKE '250.00%' AND icd_version = 9)
      )
      AND hadm_id IN (
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE (
          (icd_code LIKE 'I50%' AND icd_version = 10) OR 
          (icd_code LIKE '428%' AND icd_version = 9)
        )
      )
    )
),

medication_flags AS (
  SELECT 
    c.subject_id, 
    c.hadm_id,
    -- Check if antidiabetic was active in first 24h
    MAX(CASE WHEN (lower(p.drug) LIKE '%insulin%' OR lower(p.drug) LIKE '%metformin%' OR lower(p.drug) LIKE '%glipizide%' OR lower(p.drug) LIKE '%glyburide%' OR lower(p.drug) LIKE '%glimepiride%' OR lower(p.drug) LIKE '%pioglitazone%' OR lower(p.drug) LIKE '%empagliflozin%' OR lower(p.drug) LIKE '%dapagliflozin%' OR lower(p.drug) LIKE '%canagliflozin%' OR lower(p.drug) LIKE '%linagliptin%' OR lower(p.drug) LIKE '%saxagliptin%' OR lower(p.drug) LIKE '%sitagliptin%' OR lower(p.drug) LIKE '%exenatide%' OR lower(p.drug) LIKE '%liraglutide%' OR lower(p.drug) LIKE '%semaglutide%')
          AND p.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
          AND (p.stoptime IS NULL OR p.stoptime >= c.admittime)
          THEN 1 ELSE 0 END) AS antidiabetic_first_24h,
    
    -- Check if antidiabetic was active in final 48h
    MAX(CASE WHEN (lower(p.drug) LIKE '%insulin%' OR lower(p.drug) LIKE '%metformin%' OR lower(p.drug) LIKE '%glipizide%' OR lower(p.drug) LIKE '%glyburide%' OR lower(p.drug) LIKE '%glimepiride%' OR lower(p.drug) LIKE '%pioglitazone%' OR lower(p.drug) LIKE '%empagliflozin%' OR lower(p.drug) LIKE '%dapagliflozin%' OR lower(p.drug) LIKE '%canagliflozin%' OR lower(p.drug) LIKE '%linagliptin%' OR lower(p.drug) LIKE '%saxagliptin%' OR lower(p.drug) LIKE '%sitagliptin%' OR lower(p.drug) LIKE '%exenatide%' OR lower(p.drug) LIKE '%liraglutide%' OR lower(p.drug) LIKE '%semaglutide%')
          AND p.starttime <= c.dischtime
          AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR))
          THEN 1 ELSE 0 END) AS antidiabetic_final_48h,
    
    -- Beta-blocker flags
    MAX(CASE WHEN (lower(p.drug) LIKE '%metoprolol%' OR lower(p.drug) LIKE '%atenolol%' OR lower(p.drug) LIKE '%propranolol%' OR lower(p.drug) LIKE '%carvedilol%' OR lower(p.drug) LIKE '%labetalol%' OR lower(p.drug) LIKE '%bisoprolol%' OR lower(p.drug) LIKE '%nebivolol%')
          AND p.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
          AND (p.stoptime IS NULL OR p.stoptime >= c.admittime)
          THEN 极 ELSE 0 END) AS beta_blocker_first_24h,
    
    MAX(CASE WHEN (lower(p.drug) LIKE '%metoprolol%' OR lower(p.drug) LIKE '%atenolol%' OR lower(p极.drug) LIKE '%propranolol%' OR lower(p.drug) LIKE '%carvedilol%' OR lower(p.drug) LIKE '%labetalol%' OR lower(p.drug) LIKE '%bisoprolol%' OR lower(p.drug) LIKE '%nebivolol%')
          AND p.starttime <= c.dischtime
          AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR))
          THEN 1 ELSE 0 END) AS beta_blocker_final_48h,
    
    -- ACEi/ARB/ARNI flags
    MAX(CASE WHEN (lower(p.drug) LIKE '%lisinopril%' OR lower(p.drug) LIKE '%enalapril%' OR lower(p.drug) LIKE '%ramipril%' OR lower(p.drug) LIKE '%captopril%' OR lower(p.drug) LIKE '%losartan%' OR lower(p.drug) LIKE '%valsartan%' OR lower(p.drug) LIKE '%candesartan%' OR lower(p.drug) LIKE '%irbesartan%' OR lower(p.drug) LIKE '%olmesartan%' OR lower(p.drug) LIKE '%telmisartan%' OR lower(p.drug) LIKE '%azilsartan%' OR lower(p.drug) LIKE '%sacubitril%')
          AND p.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
          AND (p.stoptime IS NULL OR p.stoptime >= c.admittime)
          THEN 1 ELSE 0 END) AS acei_arb_arni_first_24h,
    
    MAX(CASE WHEN (lower(p.drug) LIKE '%lisinopril%' OR lower(p.drug) LIKE '%enalapril%' OR lower(p.drug) LIKE '%ramipril%' OR lower(p.drug) LIKE '%captopril%' OR lower(p.drug) LIKE '%losartan%' OR lower(p.drug) LIKE '%valsartan%' OR lower(p.drug) LIKE '%candesartan%' OR lower(p.drug) LIKE '%irbesartan%' OR lower(p.drug) LIKE '%olmesartan%' OR lower(p.drug) LIKE '%telmisartan%' OR lower(p.drug) LIKE '%azilsartan%' OR lower(p.drug) LIKE '%sacubitril%')
          AND p.starttime <= c.dischtime
          AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR))
          THEN 1 ELSE 0 END) AS acei_arb_arni_final_48h,
    
    -- Loop diuretic flags
    MAX(CASE WHEN (lower(p.drug) LIKE '%furosemide%' OR lower(p.drug) LIKE '%bumetanide%' OR lower(p.drug) LIKE '%torsemide%' OR lower(p.drug) LIKE '%ethacrynic acid%')
          AND p.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
          AND (p.stoptime IS NULL OR p.stoptime >= c.admittime)
          THEN 1 ELSE 0 END) AS loop_diuretic_first_24h,
    
    MAX(CASE WHEN (lower(p.drug) LIKE '%furosemide%' OR lower(p.drug) LIKE '%bumetanide%' OR lower(p.drug) LIKE '%torsemide%' OR lower(p.drug) LIKE '%ethacrynic acid%')
          AND p.starttime <= c.dischtime
          AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR))
          THEN 1 ELSE 0 END) AS loop_diuretic_final_48h
    
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.subject_id, c.hadm_id
)

-- Calculate percentages and counts
SELECT 
  'Antidiabetic' AS drug_class,
  ROUND(100.0 * SUM(antidiabetic_first_24h) / COUNT(*), 2) AS percent_first_24h,
  ROUND(100.0 * SUM(antidiabetic_final_48h) / COUNT(*), 2) AS percent_final_48h,
  SUM(CASE WHEN antidiabetic_first_24h = 1 AND antidiabetic_final_48h = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN antidiabetic_first_24h = 0 AND antidiabetic_final_48h = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN antidiabetic_first极_24h = 1 AND antidiabetic_final_48h = 0 THEN 1 ELSE 0 END) AS discontinued
FROM medication_flags

UNION ALL

SELECT 
  'Beta-Blocker' AS drug_class,
  ROUND(100.0 * SUM(beta_blocker_first_24h) / COUNT(*), 2) AS percent_first_24h,
  ROUND(100.0 * SUM(beta_blocker_final_48h) / COUNT(*), 2) AS percent_final_48h,
  SUM(CASE WHEN beta_blocker_first_24h = 1 AND beta_blocker_final_48h = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN beta_blocker_first_24h = 0 AND beta_blocker_final_48h = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN beta_blocker_first_24h = 1 AND beta_blocker_final_48h = 0 THEN 1 ELSE 0 END) AS discontinued
FROM medication_flags

UNION ALL

SELECT 
  'ACEi/ARB/ARNI' AS drug_class,
  ROUND(100.0 * SUM(acei_arb_arni_first_24h) / COUNT(*), 2) AS percent_first_24h,
  ROUND(100.0 * SUM(acei_arb_arni_final_48h) / COUNT(*), 2) AS percent_final_48h,
  SUM(CASE WHEN acei_arb_arni_first_24h = 1 AND acei_arb_arni_final_48h = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN acei_arb_arni_first_24h = 0 AND acei_arb_arni_final_48h = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN acei_arb_arni_first_24h = 1 AND acei_arb_arni_final_48h = 0 THEN 1 ELSE 0 END) AS discontinued
FROM medication_flags

UNION ALL

SELECT 
  'Loop Diuretic' AS drug_class,
  ROUND(100.0 * SUM(loop_diuretic_first_24h) / COUNT(*), 2) AS percent_first_24h,
  ROUND(100.0 * SUM(loop_diuretic_final_48h) / COUNT(*), 2) AS percent_final_48h,
  SUM(CASE WHEN loop_diuretic_first_24h = 1 AND loop_diuretic_final_48h = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN loop_diuretic_first_24h = 0 AND loop_diuretic_final_48h = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN loop_diuretic_first_24h = 1 AND loop_diuretic_final_48h = 0 THEN 1 ELSE 0 END) AS discontinued
FROM medication_flags;