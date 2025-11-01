WITH patients_filtered AS (
  SELECT p.subject_id, p.gender, p.anchor_age, p.anchor_year, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
),
diagnoses AS (
  SELECT di.hadm_id, di.icd_code, di.icd_version, d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
),
t2dm_hf AS (
  SELECT pf.*
  FROM patients_filtered pf
  WHERE EXISTS (
    SELECT 1 FROM diagnoses d
    WHERE d.hadm_id = pf.hadm_id
      AND d.icd_version = 10
      AND d.icd_code LIKE 'E11%'
  )
  AND EXISTS (
    SELECT 1 FROM diagnoses d
    WHERE d.hadm_id = pf.hadm_id
      AND d.icd_version = 10
      AND d.icd_code LIKE 'I50%'
  )
),
-- Define insulin and oral agent drugs
insulin_drugs AS (
  SELECT DISTINCT drug
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE LOWER(drug) LIKE '%insulin%'
),
oral_agents_list AS (
  SELECT 'metformin' AS drug UNION ALL
  SELECT 'glipizide' UNION ALL
  SELECT 'glyburide' UNION ALL
  SELECT 'glimepiride' UNION ALL
  SELECT 'sitagliptin' UNION ALL
  SELECT 'linagliptin' UNION ALL
  SELECT 'saxagliptin' UNION ALL
  SELECT 'alogliptin' UNION ALL
  SELECT 'empagliflozin' UNION ALL
  SELECT 'dapagliflozin' UNION ALL
  SELECT 'canagliflozin' UNION ALL
  SELECT 'liraglutide' UNION ALL
  SELECT 'semaglutide' UNION ALL
  SELECT 'exenatide' UNION ALL
  SELECT 'pioglitazone' UNION ALL
  SELECT 'rosiglitazone' UNION ALL
  SELECT 'acarbose' UNION ALL
  SELECT 'miglitol' UNION ALL
  SELECT 'nateglinide' UNION ALL
  SELECT 'repaglinide'
),
-- Get all prescriptions for these admissions
meds AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN oal.drug IS NOT NULL THEN 'oral_agent'
      ELSE NULL
    END AS med_class
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN t2dm_hf t ON p.hadm_id = t.hadm_id
  LEFT JOIN oral_agents_list oal ON LOWER(p.drug) = LOWER(oal.drug)
  WHERE LOWER(p.drug) LIKE '%insulin%' OR oal.drug IS NOT NULL
),
-- IV insulin in ICU
iv_insulin_items AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu`.d_items
  WHERE LOWER(label) LIKE '%insulin%' 
    AND LOWER(label) NOT LIKE '%glargine%'
    AND LOWER(label) NOT LIKE '%detemir%' 
    AND LOWER(label) NOT LIKE '%degludec%'
    AND linksto = 'inputevents'
),
iv_insulin AS (
  SELECT 
    i.hadm_id,
    i.starttime,
    i.endtime,
    'insulin' AS med_class
  FROM `physionet-data.mimiciv_3_1_icu`.inputevents i
  INNER JOIN iv_insulin_items iv ON i.itemid = iv.itemid
  INNER JOIN t2dm_hf t ON i.hadm_id = t.hadm_id
),
-- Combine all insulin and oral agents
all_meds AS (
  SELECT hadm_id, starttime, stoptime, med_class FROM meds
  UNION ALL
  SELECT hadm_id, starttime, endtime, med_class FROM iv_insulin
),
-- Define time windows and flag exposure
exposure AS (
  SELECT
    t.hadm_id,
    t.admittime,
    t.dischtime,
    -- First 24h window: admittime to admittime + 1 day
    DATETIME_ADD(t.admittime, INTERVAL 1 DAY) AS first_24h_end,
    -- Last 48h window: dischtime - 2 days to dischtime
    DATETIME_SUB(t.dischtime, INTERVAL 2 DAY) AS last_48h_start,
    am.med_class,
    -- Check if med overlaps with first 24h
    MAX(CASE 
      WHEN am.starttime < DATETIME_ADD(t.admittime, INTERVAL 1 DAY) 
       AND (am.stoptime IS NULL OR am.stoptime > t.admittime)
      THEN 1 ELSE 0 END) AS used_first_24h,
    -- Check if med overlaps with last 48h
    MAX(CASE 
      WHEN (am.stoptime IS NULL OR am.stoptime > DATETIME_SUB(t.dischtime, INTERVAL 2 DAY))
       AND am.starttime < t.dischtime
      THEN 1 ELSE 0 END) AS used_last_48h
  FROM t2dm_hf t
  LEFT JOIN all_meds am ON t.hadm_id = am.hadm_id
  GROUP BY t.hadm_id, t.admittime, t.dischtime, am.med_class
),
-- Classify status per med_class
status AS (
  SELECT
    hadm_id,
    med_class,
    used_first_24h,
    used_last_48h,
    CASE
      WHEN used_first_24h = 1 AND used_last_48h = 1 THEN 'continued'
      WHEN used_first_24h = 0 AND used_last_48h = 1 THEN 'initiated'
      WHEN used_first_24h = 1 AND used_last_48h = 0 THEN 'discontinued'
      ELSE 'none'
    END AS status
  FROM exposure
  WHERE med_class IS NOT NULL
),
-- Aggregate counts
aggregated AS (
  SELECT
    med_class,
    SUM(CASE WHEN status = 'continued' THEN 1 ELSE 0 END) AS continued_count,
    SUM(CASE WHEN status = 'initiated' THEN 1 ELSE 0 END) AS initiated_count,
    SUM(CASE WHEN status = 'discontinued' THEN 1 ELSE 0 END) AS discontinued_count,
    COUNT(*) AS total_count
  FROM status
  GROUP BY med_class
)
-- Final output: prevalence and counts
SELECT
  med_class,
  continued_count,
  initiated_count,
  discontinued_count,
  total_count,
  ROUND(100.0 * continued_count / total_count, 2) AS continued_pct,
  ROUND(100.0 * initiated_count / total_count, 2) AS initiated_pct,
  ROUND(100.0 * discontinued_count / total;