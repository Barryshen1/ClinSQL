WITH cohort AS (
  -- Select female patients aged 44-54 with hospital admissions, T2DM, and heart failure
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND i.los >= 2  -- Ensure last 48h is possible
    AND EXISTS (
      -- T2DM: ICD-10 E11.*
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
        ON d.icd_code = icd.icd_code AND d.icd_version = CAST(icd.icd_version AS STRING)
      WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
        AND d.icd_version = '10' AND d.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      -- Heart failure: ICD-10 I50.*
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
        ON d.icd_code = icd.icd_code AND d.icd_version = CAST(icd.icd_version AS STRING)
      WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
        AND d.icd_version = '10' AND d.icd_code LIKE 'I50%'
    )
),
insulin_first24 AS (
  -- Insulin in first 24h (ICU inputs only, as IV insulin is key in critical care)
  SELECT 
    c.subject_id,
    c.hadm_id,
    1 AS has_insulin_first24
  FROM cohort c
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    INNER JOIN `physionet-data.mimiciv_3_1_icu.ingredientevents` ing
      ON ie.stay_id = ing.stay_id AND ie.orderid = ing.orderid
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON ing.stay_id = i.stay_id
    WHERE i.hadm_id = c.hadm_id
      AND ing.itemid IN (225798, 50006, 225835, 225834, 225833)  -- Common insulin itemids
      AND ing.amount > 0
      AND ing.starttime >= c.intime
      AND ing.starttime < TIMESTAMP_ADD(c.intime, INTERVAL 1 DAY)
  )
),
insulin_last48 AS (
  -- Insulin in last 48h
  SELECT 
    c.subject_id,
    c.hadm_id,
    1 AS has_insulin_last48
  FROM cohort c
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
    INNER JOIN `physionet-data.mimiciv_3_1_icu.ingredientevents` ing
      ON ie.stay_id = ing.stay_id AND ie.orderid = ing.orderid
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
      ON ing.stay_id = i.stay_id
    WHERE i.hadm_id = c.hadm_id
      AND ing.itemid IN (225798, 50006, 225835, 225834, 225833)
      AND ing.amount > 0
      AND ing.starttime > TIMESTAMP_SUB(c.outtime, INTERVAL 2 DAY)
      AND ing.starttime <= c.outtime
  )
),
oral_first24 AS (
  -- Oral agents in first 24h (hospital-wide prescriptions)
  SELECT 
    c.subject_id,
    c.hadm_id,
    1 AS has_oral_first24
  FROM cohort c
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE pr.subject_id = c.subject_id
      AND pr.hadm_id = c.hadm_id
      AND (pr.drug LIKE '%METFORMIN%' 
         OR pr.drug LIKE '%GLIPIZIDE%' 
         OR pr.drug LIKE '%GLYBURIDE%' 
         OR pr.drug LIKE '%SITAGLIPTIN%' 
         OR pr.drug LIKE '%GLIMEPIRIDE%' 
         OR pr.drug LIKE '%PIOGLITAZONE%' 
         OR pr.drug LIKE '%EMPAGLIFLOZIN%' 
         OR pr.drug LIKE '%DPP-4%' 
         OR pr.drug LIKE '%SGLT2%')
      AND pr.starttime >= c.intime
      AND pr.starttime < TIMESTAMP_ADD(c.intime, INTERVAL 1 DAY)
  )
),
oral_last48 AS (
  -- Oral agents in last 48h
  SELECT 
    c.subject_id,
    c.hadm_id,
    1 AS has_oral_last48
  FROM cohort c
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    WHERE pr.subject_id = c.subject_id
      AND pr.hadm_id = c.hadm_id
      AND (pr.drug LIKE '%METFORMIN%' 
         OR pr.drug LIKE '%GLIPIZIDE%' 
         OR pr.drug LIKE '%GLYBURIDE%' 
         OR pr.drug LIKE '%SITAGLIPTIN%' 
         OR pr.drug LIKE '%GLIMEPIRIDE%' 
         OR pr.drug LIKE '%PIOGLITAZONE%' 
         OR pr.drug LIKE '%EMPAGLIFLOZIN%' 
         OR pr.drug LIKE '%DPP-4%' 
         OR pr.drug LIKE '%SGLT2%')
      AND pr.starttime > TIMESTAMP_SUB(c.outtime, INTERVAL 2 DAY)
      AND pr.starttime <= c.outtime
  )
)
-- Main aggregation
SELECT 
  'Insulin' AS medication_type,
  -- Prevalence
  ROUND(AVG(COALESCE(if1.has_insulin_first24, 0)) * 100, 2) AS prevalence_first24_pct,
  ROUND(AVG(COALESCE(il.has_insulin_last48, 0)) * 100, 2) AS prevalence_last48_pct,
  -- Counts
  SUM(COALESCE(if1.has_insulin_first24, 0)) AS count_first24,
  SUM(COALESCE(il.has_insulin_last48, 0)) AS count_last48,
  SUM(CASE WHEN COALESCE(if1.has_insulin_first24, 0) = 1 AND COALESCE(il.has_insulin_last48, 0) = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN COALESCE(if1.has_insulin_first24, 0) = 0 AND COALESCE(il.has_insulin_last48, 0) = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN COALESCE(if1.has_insulin_first24, 0) = 1 AND COALESCE(il.has_insulin_last48, 0) = 0 THEN 1 ELSE 0 END) AS discontinued,
  COUNT(*) AS total_admissions
FROM cohort c
LEFT JOIN insulin_first24 if1 ON c.subject_id = if1.subject_id AND c.hadm_id = if1.hadm_id
LEFT JOIN insulin_last48 il ON c.subject_id = il.subject_id AND c.hadm_id = il.hadm_id

UNION ALL

SELECT 
  'Oral Agent' AS medication_type,
  ROUND(AVG(COALESCE(of1.has_oral_first24, 0)) * 100, 2) AS prevalence_first24_pct,
  ROUND(AVG(COALESCE(ol.has_oral_last48, 0)) * 100, 2) AS prevalence_last48_pct,
  SUM(COALESCE(of1.has_oral_first24, 0)) AS count_first24,
  SUM(COALESCE(ol.has_oral_last48, 0)) AS count_last48,
  SUM(CASE WHEN COALESCE(of1.has_oral_first24, 0) = 1 AND COALESCE(ol.has_oral_last48, 0) = 1 THEN 1 ELSE 0 END) AS continued,
  SUM(CASE WHEN COALESCE(of1.has_oral_first24, 0) = 0 AND COALESCE(ol.has_oral_last48, 0) = 1 THEN 1 ELSE 0 END) AS initiated,
  SUM(CASE WHEN COALESCE(of1.has_oral_first24, 0) = 1 AND COALESCE(ol.has_oral_last48, 0) = 0 THEN 1 ELSE 0 END) AS discontinued,
  COUNT(*) AS total_admissions
FROM cohort c
LEFT JOIN oral_first24 of1 ON c.subject_id = of1.subject_id AND c.hadm_id = of1.hadm_id
LEFT JOIN oral_last48 ol ON c.subject_id = ol.subject_id AND c.hadm_id = ol.hadm_id;