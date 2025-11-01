WITH cohort_patients AS (
  -- Females 86-96
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 86 AND 96
),

dm_codes AS (
  -- Diabetes ICD codes
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 'ICD-9' AND icd_code LIKE '250.%')
     OR (icd_version = 'ICD-10' AND icd_code LIKE 'E1[0-4]%')
),

hf_codes AS (
  -- Heart failure ICD codes
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 'ICD-9' AND icd_code LIKE '428.%')
     OR (icd_version = 'ICD-10' AND icd_code LIKE 'I50%')
),

cohort_admissions AS (
  -- Inpatient admissions for cohort patients with DM and HF
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort_patients p ON a.subject_id = p.subject_id
  WHERE a.admission_type IN ('EMERGENCY', 'ELECTIVE', 'URGENT')
    AND a.hospital_expire_flag = 0
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN dm_codes dm ON d.icd_code = dm.icd_code AND d.icd_version = dm.icd_version
      WHERE d.hadm_id = a.hadm_id
    )
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      INNER JOIN hf_codes hf ON d.icd_code = hf.icd_code AND d.icd_version = hf.icd_version
      WHERE d.hadm_id = a.hadm_id
    )
),

insulin_itemids AS (
  SELECT itemid FROM UNNEST([225798, 225799, 225834, 225835, 225836, 220359, 227977, 3004245, 3004246]) AS itemid
),

oral_itemids AS (
  SELECT itemid FROM UNNEST([225916, 225560, 225621, 225607, 225624, 225653, 225655]) AS itemid  -- Metformin, glipizide, glyburide, etc.
),

diabetes_items AS (
  SELECT itemid, 'Insulin' AS med_class FROM insulin_itemids
  UNION ALL
  SELECT itemid, 'Oral Agents' AS med_class FROM oral_itemids
),

cohort_stays AS (
  -- ICU stays for cohort admissions
  SELECT cs.subject_id, cs.hadm_id, i.stay_id, i.intime, i.outtime, i.los
  FROM cohort_admissions cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON cs.hadm_id = i.hadm_id
  WHERE i.los >= 1  -- At least 1h stay
),

stay_flags AS (
  -- For each stay and class, flag early/late med presence
  SELECT 
    cs.stay_id,
    cs.subject_id,
    cs.hadm_id,
    di.med_class,
    -- Early: any event in first 12h
    LOGICAL_OR(
      ie.starttime >= cs.intime 
      AND ie.starttime < TIMESTAMP_ADD(cs.intime, INTERVAL 12 HOUR)
      AND ie.amount > 0
    ) AS has_early,
    -- Late: any event in last 72h (clipped if LOS <72h)
    LOGICAL_OR(
      ie.starttime >= GREATEST(cs.intime, TIMESTAMP_SUB(cs.outtime, INTERVAL 72 HOUR))
      AND ie.starttime <= cs.outtime
      AND ie.amount > 0
    ) AS has_late
  FROM cohort_stays cs
  CROSS JOIN (SELECT DISTINCT med_class FROM diabetes_items) di
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie 
    ON cs.subject_id = ie.subject_id 
    AND cs.hadm_id = ie.hadm_id 
    AND cs.stay_id = ie.stay_id
    AND ie.itemid IN (SELECT itemid FROM diabetes_items WHERE med_class = di.med_class)
    AND ie.statusdescription != 'Rewritten'
  GROUP BY cs.stay_id, cs.subject_id, cs.hadm_id, di.med_class
),

stay_summary AS (
  -- Per-stay summary with class flags and transitions
  SELECT 
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    -- Early/late flags per class
    MAX(CASE WHEN s.med_class = 'Insulin' THEN CAST(s.has_early AS INT64) END) AS early_insulin,
    MAX(CASE WHEN s.med_class = 'Insulin' THEN CAST(s.has_late AS INT64) END) AS late_insulin,
    MAX(CASE WHEN s.med_class = 'Oral Agents' THEN CAST(s.has_early AS INT64) END) AS early_oral,
    MAX(CASE WHEN s.med_class = 'Oral Agents' THEN CAST(s.has_late AS INT64) END) AS late_oral,
    -- Early-to-late transitions (mutually exclusive per stay)
    CASE 
      WHEN MAX(CASE WHEN s.med_class = 'Insulin' THEN CAST(s.has_early AS INT64) END) = 1 
           AND MAX(CASE WHEN s.med_class = 'Insulin' THEN CAST(s.has_late AS INT64) END) = 1 
           AND MAX(CASE WHEN s.med_class = 'Oral Agents' THEN CAST(s.has_early AS INT64) END) = 0 THEN 1 
      ELSE 0 
    END AS transition_insulin_to_insulin,
    CASE 
      WHEN MAX(CASE WHEN s.med_class = 'Insulin' THEN CAST(s.has_early AS INT64) END) = 0 
           AND MAX(CASE WHEN s.med_class = 'Insulin' THEN CAST(s.has_late AS INT64) END) = 1 
           AND MAX(CASE WHEN s.med_class = 'Oral Agents' THEN CAST(s.has_early AS INT64) END) = 1 
           AND MAX(CASE WHEN s.med_class = 'Oral Agents' THEN CAST(s.has_late AS INT64) END) = 0 THEN 1 
      ELSE 0 
    END AS transition_oral_to_insulin,
    CASE 
      WHEN MAX(CASE WHEN s.med_class = 'Oral Agents' THEN CAST(s.has_early AS INT64) END) = 1 
           AND MAX(CASE WHEN s.med_class = 'Oral Agents' THEN CAST(s.has_late AS INT64) END) = 1 
           AND MAX(CASE WHEN s.med_class = 'Insulin' THEN CAST(s.has_early AS INT64) END) = 0 THEN 1 
      ELSE 0 
    END AS transition_oral_to_oral
  FROM stay_flags s
  GROUP BY s.stay_id, s.subject_id, s.hadm_id
),

class_aggregated AS (
  -- Rates by class (% of stays with usage)
  SELECT 
    'Insulin' AS med_class,
    AVG(early_insulin) * 100 AS early_rate_pct,
    AVG(late_insulin) * 100 AS late_rate_pct,
    COUNT(*) AS n_stays
  FROM stay_summary
  
  UNION ALL
  
  SELECT 
    'Oral Agents' AS med_class,
    AVG(early_oral) * 100 AS early_rate_pct,
    AVG(late_oral) * 100 AS late_rate_pct,
    COUNT(*) AS n_stays
  FROM stay_summary
),

transitions AS (
  -- Early-to-late transitions (% among stays with early usage)
  SELECT 
    'Insulin to Insulin' AS transition,
    (SUM(transition_insulin_to_insulin) * 100.0 / NULLIF(SUM(early_insulin), 0)) AS rate_pct,
    SUM(early_insulin) AS denom_early
  FROM stay_summary
  WHERE early_insulin = 1
  
  UNION ALL
  
  SELECT 
    'Oral to Insulin' AS transition,
    (SUM(transition_oral_to_insulin) * 100.0 / NULLIF(SUM(early_oral), 0)) AS rate_pct,
    SUM(early_oral) AS denom_early
  FROM stay_summary
  WHERE early_oral = 1
  
  UNION ALL
  
  SELECT 
    'Oral to Oral' AS transition,
    (SUM(transition_oral_to_oral) * 100.0 / NULLIF(SUM(early_oral), 0)) AS rate_pct,
    SUM(early_oral) AS denom_early
  FROM stay_summary
  WHERE early_oral = 1
)

-- Main results: Rates by class and transitions
SELECT 'Rates by Class' AS section, med_class, ROUND(early_rate_pct, 1) AS early_rate_pct, ROUND(late_rate_pct, 1) AS late_rate_pct, n_stays
FROM class_aggregated

UNION ALL

SELECT 'Transitions' AS section, transition AS med_class, ROUND(rate_pct, 1) AS early_rate_pct, NULL AS late_rate_pct, denom_early AS n_stays
FROM transitions
ORDER BY section, med_class;