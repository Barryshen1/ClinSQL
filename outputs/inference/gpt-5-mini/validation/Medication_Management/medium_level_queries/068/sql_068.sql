WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  -- join diagnoses to filter for T2DM + HF per admission
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    USING(subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code
   AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, p.anchor_age
  HAVING
    -- At least one T2DM code/text on the admission (ICD-10 E11% or ICD-9 250% or textual 'type 2')
    SUM(CASE
          WHEN (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
            OR (d.icd_version = 9  AND d.icd_code LIKE '250%')
            OR LOWER(icd.long_title) LIKE '%type 2%'
            OR LOWER(icd.long_title) LIKE '%type ii%'
          THEN 1 ELSE 0 END) >= 1
    AND
    -- At least one heart failure code/text on the admission (ICD-10 I50% or ICD-9 428% or textual)
    SUM(CASE
          WHEN (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
            OR (d.icd_version = 9  AND d.icd_code LIKE '428%')
            OR LOWER(icd.long_title) LIKE '%heart failure%'
          THEN 1 ELSE 0 END) >= 1
),

-- Combine medication/administration events from several hospital and ICU sources.
med_events AS (
  -- prescriptions (orders)
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    pr.starttime AS event_time,
    LOWER(COALESCE(pr.drug, '')) AS drug_text,
    'prescription' AS src
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
  WHERE pr.starttime IS NOT NULL

  UNION ALL

  -- pharmacy (dispensations)
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ph.starttime AS event_time,
    LOWER(COALESCE(ph.medication, '')) AS drug_text,
    'pharmacy' AS src
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.hadm_id = c.hadm_id
  WHERE ph.starttime IS NOT NULL

  UNION ALL

  -- emar (electronic medication administration records)
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    e.charttime AS event_time,
    LOWER(COALESCE(e.medication, '')) AS drug_text,
    'emar' AS src
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON e.hadm_id = c.hadm_id
  WHERE e.charttime IS NOT NULL

  UNION ALL

  -- ICU inputevents (item label via d_items)
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ie.starttime AS event_time,
    LOWER(COALESCE(di.label, '')) AS drug_text,
    'icu_input' AS src
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON ie.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE ie.starttime IS NOT NULL

  UNION ALL

  -- ICU ingredientevents (also captures syringe/ingredient labels)
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ig.starttime AS event_time,
    LOWER(COALESCE(di.label, '')) AS drug_text,
    'icu_ingredient' AS src
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.ingredientevents` ig
    ON ig.hadm_id = c.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ig.itemid = di.itemid
  WHERE ig.starttime IS NOT NULL
),

-- Classify events into sliding-scale / basal / bolus / other using keyword matching.
meds_classified AS (
  SELECT
    me.* EXCEPT(src),
    me.src,
    CASE
      -- sliding-scale detection first
      WHEN drug_text LIKE '%sliding%' OR drug_text LIKE '%sliding scale%' OR drug_text LIKE '%sliding-scale%' OR drug_text LIKE '%ssi%' THEN 'sliding-scale'

      -- basal insulin keywords
      WHEN drug_text LIKE '%glargine%' OR drug_text LIKE '%lantus%' OR drug_text LIKE '%toujeo%' OR
           drug_text LIKE '%detemir%' OR drug_text LIKE '%levemir%' OR
           drug_text LIKE '%degludec%' OR drug_text LIKE '%tresiba%' OR
           drug_text LIKE '%basaglar%' OR drug_text LIKE '%nph%' OR
           drug_text LIKE '%isophane%' THEN 'basal'

      -- bolus / rapid/short-acting insulin keywords (and generic 'insulin' fallback)
      WHEN drug_text LIKE '%regular insulin%' OR drug_text LIKE '%regular%' OR
           drug_text LIKE '%lispro%' OR drug_text LIKE '%humalog%' OR
           drug_text LIKE '%aspart%' OR drug_text LIKE '%novolog%' OR
           drug_text LIKE '%apidra%' OR drug_text LIKE '%glulisine%' OR
           drug_text LIKE '%short-acting%' OR drug_text LIKE '%rapid-acting%' OR
           -- generic insulin keyword (if no basal keyword matched above)
           drug_text LIKE '%insulin%' THEN 'bolus'

      ELSE NULL
    END AS regimen_class
  FROM med_events me
),

-- Keep only classified insulin events (non-null regimen_class)
insulin_events AS (
  SELECT *
  FROM meds_classified
  WHERE regimen_class IS NOT NULL
),

-- For each admission, compute binary flags for presence of basal/bolus/sliding in first 48h and final 12h.
med_flags_raw AS (
  SELECT
    c.hadm_id,
    -- First 48h window
    MAX(CASE WHEN ie.regimen_class = 'basal' AND ie.event_time BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS basal_first48,
    MAX(CASE WHEN ie.regimen_class = 'bolus' AND ie.event_time BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS bolus_first48,
    MAX(CASE WHEN ie.regimen_class = 'sliding-scale' AND ie.event_time BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END) AS sliding_first48,

    -- Final 12h window (only meaningful if dischtime is not NULL)
    MAX(CASE WHEN ie.regimen_class = 'basal' AND ie.event_time BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS basal_final12,
    MAX(CASE WHEN ie.regimen_class = 'bolus' AND ie.event_time BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS bolus_final12,
    MAX(CASE WHEN ie.regimen_class = 'sliding-scale' AND ie.event_time BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS sliding_final12
  FROM cohort c
  LEFT JOIN insulin_events ie
    ON ie.hadm_id = c.hadm_id
  GROUP BY c.hadm_id
),

-- Ensure zeros for admissions without any events captured
med_flags AS (
  SELECT
    c.hadm_id,
    COALESCE(m.basal_first48, 0) AS basal_first48,
    COALESCE(m.bolus_first48, 0) AS bolus_first48,
    COALESCE(m.sliding_first48, 0) AS sliding_first48,
    COALESCE(m.basal_final12, 0) AS basal_final12,
    COALESCE(m.bolus_final12, 0) AS bolus_final12,
    COALESCE(m.sliding_final12, 0) AS sliding_final12
  FROM cohort c
  LEFT JOIN med_flags_raw m
    USING(hadm_id)
  -- Exclude admissions without a discharge time for the final-12h window analysis
  WHERE c.dischtime IS NOT NULL
),

-- Compute per-admission basal-bolus presence within each window
med_flags_with_bb AS (
  SELECT
    *,
    CASE WHEN basal_first48 = 1 AND bolus_first48 = 1 THEN 1 ELSE 0 END AS basal_bolus_first48,
    CASE WHEN basal_final12 = 1 AND bolus_final12 = 1 THEN 1 ELSE 0 END AS basal_bolus_final12
  FROM med_flags
),

-- Aggregation: counts and percentages
summary AS (
  SELECT
    COUNT(*) AS total_admissions,
    SUM(basal_first48) AS count_basal_first48,
    SUM(basal_final12) AS count_basal_final12,
    SUM(bolus_first48) AS count_bolus_first48,
    SUM(bolus_final12) AS count_bolus_final12,
    SUM(basal_bolus_first48) AS count_basal_bolus_first48,
    SUM(basal_bolus_final12) AS count_basal_bolus_final12,
    SUM(sliding_first48) AS count_sliding_first48,
    SUM(sliding_final12) AS count_sliding_final12
  FROM med_flags_with_bb
)

SELECT
  'Basal' AS regimen,
  ROUND(100.0 * count_basal_first48 / NULLIF(total_admissions,0), 2) AS pct_first48,
  ROUND(100.0 * count_basal_final12 / NULLIF(total_admissions,0), 2) AS pct_final12,
  ROUND(100.0 * (count_basal_final12 - count_basal_first48) / NULLIF(total_admissions,0), 2) AS net_change
FROM summary

UNION ALL

SELECT
  'Bolus' AS regimen,
  ROUND(100.0 * count_bolus_first48 / NULLIF(total_admissions,0), 2) AS pct_first48,
  ROUND(100.0 * count_bolus_final12 / NULLIF(total_admissions,0), 2) AS pct_final12,
  ROUND(100.0 * (count_bolus_final12 - count_bolus_first48) / NULLIF(total_admissions,0), 2) AS net_change
FROM summary

UNION ALL

SELECT
  'Basal-Bolus (both present in window)' AS regimen,
  ROUND(100.0 * count_basal_bolus_first48 / NULLIF(total_admissions,0), 2) AS pct_first48,
  ROUND(100.0 * count_basal_bolus_final12 / NULLIF(total_admissions,0), 2) AS pct_final12,
  ROUND(100.0 * (count_basal_bolus_final12 - count_basal_bolus_first48) / NULLIF(total_admissions,0), 2) AS net_change
FROM summary

UNION ALL

SELECT
  'Sliding-scale' AS regimen,
  ROUND(100.0 * count_sliding_first48 / NULLIF(total_admissions,0), 2) AS pct_first48,
  ROUND(100.0 * count_sliding_final12 / NULLIF(total_admissions,0), 2) AS pct_final12,
  ROUND(100.0 * (count_sliding_final12 - count_sliding_first48) / NULLIF(total_admissions,0), 2) AS net_change
FROM summary
;