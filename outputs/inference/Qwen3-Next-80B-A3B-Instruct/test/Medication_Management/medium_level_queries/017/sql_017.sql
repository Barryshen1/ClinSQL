WITH cohort AS (
  SELECT DISTINCT
    i.stay_id,
    i.intime,
    i.outtime,
    p.subject_id
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON i.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND i.los >= 6  -- 6 days = 144 hours
    AND (
      -- Diabetes: ICD-9 250.x, ICD-10 E10-E14
      (d.icd_version = 9 AND d.icd_code LIKE '250%')
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR d.icd_code LIKE 'E14%'))
    )
    AND (
      -- Heart failure: ICD-9 428.x, ICD-10 I50.x
      (d.icd_version = 9 AND d.icd_code LIKE '428%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
    )
),

drug_classes AS (
  SELECT 'antidiabetic' AS drug_class, label FROM UNNEST([
    'insulin', 'metformin', 'glipizide', 'glyburide', 'glimepiride', 'pioglitazone', 'rosiglitazone',
    'liraglutide', 'semaglutide', 'exenatide', 'dulaglutide', 'canagliflozin', 'dapagliflozin', 'empagliflozin', 'glucagon'
  ]) AS label
  UNION ALL
  SELECT 'beta_blocker' AS drug_class, label FROM UNNEST([
    'metoprolol', 'atenolol', 'carvedilol', 'propranolol', 'bisoprolol', 'nadolol', 'labetalol', 'timolol'
  ]) AS label
  UNION ALL
  SELECT 'acei_arb_arni' AS drug_class, label FROM UNNEST([
    'lisinopril', 'enalapril', 'ramipril', 'captopril', 'benazepril', 'trandolapril', 'quinapril', 'fosinopril',
    'losartan', 'valsartan', 'irbesartan', 'candesartan', 'telmisartan', 'olmesartan', 'sacubitril'
  ]) AS label
  UNION ALL
  SELECT 'loop_diuretic' AS drug_class, label FROM UNNEST([
    'furosemide', 'bumetanide', 'torsemide'
  ]) AS label
),

medication_exposure AS (
  SELECT
    c.stay_id,
    dc.drug_class,
    MAX(CASE WHEN ie.starttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS in_first_72h,
    MAX(CASE WHEN ie.starttime BETWEEN TIMESTAMP_SUB(c.outtime, INTERVAL 72 HOUR) AND c.outtime THEN 1 ELSE 0 END) AS in_final_72h
  FROM cohort c
  INNER JOIN physionet-data.mimiciv_3_1_icu.inputevents ie
    ON c.stay_id = ie.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ie.itemid = di.itemid
  INNER JOIN drug_classes dc
    ON LOWER(di.label) LIKE '%' || LOWER(dc.label) || '%'
  GROUP BY c.stay_id, dc.drug_class
)

SELECT
  drug_class,
  AVG(in_first_72h) * 100 AS pct_first_72h,
  AVG(in_final_72h) * 100 AS pct_final_72h,
  SUM(CASE WHEN in_first_72h = 0 AND in_final_72h = 1 THEN 1 ELSE 0 END) AS count_initiated,
  SUM(CASE WHEN in_first_72h = 1 AND in_final_72h = 0 THEN 1 ELSE 0 END) AS count_discontinued,
  SUM(CASE WHEN in_first_72h = 1 AND in_final_72h = 1 THEN 1 ELSE 0 END) AS count_continued
FROM medication_exposure
GROUP BY drug_class
ORDER BY drug_class;