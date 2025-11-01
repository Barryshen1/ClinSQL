WITH cohort AS (
  SELECT 
    i.subject_id, 
    i.hadm_id, 
    i.stay_id,
    i.intime,
    i.outtime,
    DATETIME_ADD(i.intime, INTERVAL 72 HOUR) AS first_72h_end,
    DATETIME_SUB(i.outtime, INTERVAL 72 HOUR) AS final_72h_start
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND i.los >= 6  -- 144 hours = 6 days
    AND i.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code LIKE '250%') OR
        (icd_version = 10 AND icd_code LIKE 'E1%')  -- Diabetes codes
    )
    AND i.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code LIKE '428%') OR
        (icd_version = 10 AND icd_code LIKE 'I50%')  -- Heart failure codes
    )
),

medication_flags AS (
  SELECT 
    c.subject_id,
    c.stay_id,
    -- Antidiabetic flags
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(e.medication), r'(?i)\b(insulin|metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|exenatide|liraglutide|dulaglutide|semaglutide|acarbose|miglitol|nateglinide|repaglinide|canagliflozin|dapagliflozin|empagliflozin)\b') 
          AND e.charttime BETWEEN c.intime AND c.first_72h_end THEN 1 ELSE 0 END) AS antidiabetic_first,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(e.medication), r'(?i)\b(insulin|metformin|glipizide|glyburide|glimepiride|pioglitazone|rosiglitazone|sitagliptin|saxagliptin|linagliptin|exenatide|liraglutide|dulaglutide|semaglutide|acarbose|miglitol|nateglinide|repaglinide|canagliflozin|dapagliflozin|empagliflozin)\b') 
          AND e.charttime BETWEEN c.final_72h_start AND c.outtime THEN 1 ELSE 0 END) AS antidiabetic_final,
    -- Beta-blocker flags
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(e.medication), r'(?i)\b(propranolol|metoprolol|atenolol|bisoprolol|carvedilol|labetalol|nadolol|nebivolol|sotalol)\b') 
          AND e.charttime BETWEEN c.intime AND c.first_72h_end THEN 1 ELSE 0 END) AS beta_blocker_first,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(e.medication), r'(?i)\b(propranolol|metoprolol|atenolol|bisoprolol|carvedilol|labetalol|nadolol|nebivolol|sotalol)\b') 
          AND e.charttime BETWEEN c.final_72h_start AND c.outtime THEN 1 ELSE 0 END) AS beta_blocker_final,
    -- ACEi/ARB/ARNI flags
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(e.medication), r'(?i)\b(captopril|enalapril|lisinopril|ramipril|perindopril|quinapril|fosinopril|trandolapril|benazepril|moexipril|losartan|valsartan|irbesartan|candesartan|telmisartan|olmesartan|eprosartan|azilsartan|sacubitril/valsartan|entresto)\b') 
          AND e.charttime BETWEEN c.intime AND c.first_72h_end THEN 1 ELSE 0 END) AS acei_arb_arni_first,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(e.medication), r'(?i)\b(captopril|enalapril|lisinopril|ramipril|perindopril|quinapril|fosinopril|trandolapril|benazepril|moexipril|losartan|valsartan|irbesartan|candesartan|telmisartan|olmesartan|eprosartan|azilsartan|sacubitril/valsartan|entresto)\b') 
          AND e.charttime BETWEEN c.final_72h_start AND c.outtime THEN 1 ELSE 0 END) AS acei_arb_arni_final,
    -- Loop diuretic flags
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(e.medication), r'(?i)\b(furosemide|bumetanide|torsemide|ethacrynic acid)\b') 
          AND e.charttime BETWEEN c.intime AND c.first_72h_end THEN 1 ELSE 0 END) AS loop_diuretic_first,
    MAX(CASE WHEN REGEXP_CONTAINS(LOWER(e.medication), r'(?i)\b(furosemide|bumetanide|torsemide|ethacrynic acid)\b') 
          AND e.charttime BETWEEN c.final_72h_start AND c.outtime THEN 1 ELSE 0 END) AS loop_diuretic_final
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id
    AND c.hadm_id = e.hadm_id
    AND e.charttime BETWEEN c.intime AND c.outtime
  GROUP BY c.subject_id, c.stay_id
)

SELECT 
  'antidiabetic' AS drug_class,
  COUNT(*) AS total_patients,
  SUM(antidiabetic_first) AS count_first_72h,
  SUM(antidiabetic_final) AS count_final_72h,
  ROUND(SUM(antidiabetic_first) * 100.0 / COUNT(*), 2) AS pct_first_72h,
  ROUND(SUM(antidiabetic_final) * 100.0 / COUNT(*), 2) AS pct_final_72h,
  SUM(CASE WHEN antidiabetic_first = 1 AND antidiabetic_final = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN antidiabetic_first = 0 AND antidiabetic_final = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN antidiabetic_first = 1 AND antidiabetic_final = 0 THEN 1 ELSE 0 END) AS discontinued
FROM medication_flags

UNION ALL

SELECT 
  'beta_blocker' AS drug_class,
  COUNT(*),
  SUM(beta_blocker_first),
  SUM(beta_blocker_final),
  ROUND(SUM(beta_blocker_first) * 100.0 / COUNT(*), 2),
  ROUND(SUM(beta_blocker_final) * 100.0 / COUNT(*), 2),
  SUM(CASE WHEN beta_blocker_first = 1 AND beta_blocker_final = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN beta_blocker_first = 0 AND beta_blocker_final = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN beta_blocker_first = 1 AND beta_blocker_final = 0 THEN 1 ELSE 0 END)
FROM medication_flags

UNION ALL

SELECT 
  'acei_arb_arni' AS drug_class,
  COUNT(*),
  SUM(acei_arb_arni_first),
  SUM(acei_arb_arni_final),
  ROUND(SUM(acei_arb_arni_first) * 100.0 / COUNT(*), 2),
  ROUND(SUM(acei_arb_arni_final) * 100.0 / COUNT(*), 2),
  SUM(CASE WHEN acei_arb_arni_first = 1 AND acei_arb_arni_final = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN acei_arb_arni_first = 0 AND acei_arb_arni_final = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN acei_arb_arni_first = 1 AND acei_arb_arni_final = 0 THEN 1 ELSE 0 END)
FROM medication_flags

UNION ALL

SELECT 
  'loop_diuretic' AS drug_class,
  COUNT(*),
  SUM(loop_diuretic_first),
  SUM(loop_diuretic_final),
  ROUND(SUM(loop_diuretic_first) * 100.0 / COUNT(*), 2),
  ROUND(SUM(loop_diuretic_final) * 100.0 / COUNT(*), 2),
  SUM(CASE WHEN loop_diuretic_first = 1 AND loop_diuretic_final = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN loop_diuretic_first = 0 AND loop_diuretic_final = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN loop_diuretic_first = 1 AND loop_diuretic_final = 0 THEN 1 ELSE 0 END)
FROM medication_flags;