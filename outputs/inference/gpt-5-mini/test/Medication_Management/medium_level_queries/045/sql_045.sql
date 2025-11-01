WITH cohort AS (
  -- Female inpatients age 54-64 with BOTH diabetes and heart failure diagnoses
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 54 AND 64
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- has diabetes diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabet%'
    )
    -- has heart failure diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
        ON di2.icd_code = dd2.icd_code
        AND di2.icd_version = dd2.icd_version
      WHERE di2.hadm_id = a.hadm_id
        AND (LOWER(dd2.long_title) LIKE '%heart fail%'
             OR LOWER(dd2.long_title) LIKE '%congestive heart%')
    )
),

med_events AS (
  -- HOSP prescriptions
  SELECT
    subject_id,
    hadm_id,
    starttime AS med_time,
    LOWER(COALESCE(drug, '')) AS med_name
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE starttime IS NOT NULL

  UNION ALL

  -- HOSP pharmacy dispensing records
  SELECT
    subject_id,
    hadm_id,
    starttime AS med_time,
    LOWER(COALESCE(medication, '')) AS med_name
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE starttime IS NOT NULL

  UNION ALL

  -- HOSP emar administrations (charttime)
  SELECT
    subject_id,
    hadm_id,
    charttime AS med_time,
    LOWER(COALESCE(medication, '')) AS med_name
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE charttime IS NOT NULL

  UNION ALL

  -- ICU inputevents (may record medication/order text)
  SELECT
    subject_id,
    hadm_id,
    starttime AS med_time,
    LOWER(COALESCE(ordercategoryname, '') || ' ' || COALESCE(ordercomponenttypedescription, '') || ' ' || COALESCE(ordercategorydescription, '')) AS med_name
  FROM `physionet-data.mimiciv_3_1_icu.inputevents`
  WHERE starttime IS NOT NULL

  UNION ALL

  -- ICU ingredientevents (use available columns: itemid, statusdescription, amount)
  SELECT
    subject_id,
    hadm_id,
    starttime AS med_time,
    LOWER(
      COALESCE(CAST(itemid AS STRING), '')
      || ' '
      || COALESCE(statusdescription, '')
      || ' '
      || COALESCE(CAST(amount AS STRING), '')
    ) AS med_name
  FROM `physionet-data.mimiciv_3_1_icu.ingredientevents`
  WHERE starttime IS NOT NULL
),

meds_in_admission AS (
  -- join med events to cohort admissions and keep only events that fall within the admission window
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    m.med_time,
    m.med_name
  FROM cohort c
  JOIN med_events m
    ON m.hadm_id = c.hadm_id
  WHERE m.med_time BETWEEN c.admittime AND c.dischtime
),

per_admission_flags AS (
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    -- compute bounded window endpoints
    -- first 12 hours end = least(dischtime, admittime + 12 hours)
    LEAST(TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR), dischtime) AS first12_end,
    -- final 48 hours start = greatest(admittime, dischtime - 48 hours)
    GREATEST(admittime, TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR)) AS final48_start,
    -- flags: 1 if at least one med matching pattern in the window, else 0
    MAX(CASE
          WHEN med_time BETWEEN admittime AND LEAST(TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR), dischtime)
           AND REGEXP_CONTAINS(med_name,
             r'(insulin|glargine|detemir|lispro|aspart|degludec|glulisine|humalog|lantus|novolog|levemir)')
          THEN 1 ELSE 0 END) AS insulin_first12,
    MAX(CASE
          WHEN med_time BETWEEN admittime AND LEAST(TIMESTAMP_ADD(admittime, INTERVAL 12 HOUR), dischtime)
           AND REGEXP_CONTAINS(med_name,
             r'(metformin|glipizide|glyburide|glimepiride|sitagliptin|linagliptin|saxagliptin|repaglinide|nateglinide|pioglitazone|rosiglitazone|acarbose|miglitol|tolbutamide|chlorpropamide)')
          THEN 1 ELSE 0 END) AS oral_first12,
    MAX(CASE
          WHEN med_time BETWEEN GREATEST(admittime, TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR)) AND dischtime
           AND REGEXP_CONTAINS(med_name,
             r'(insulin|glargine|detemir|lispro|aspart|degludec|glulisine|humalog|lantus|novolog|levemir)')
          THEN 1 ELSE 0 END) AS insulin_final48,
    MAX(CASE
          WHEN med_time BETWEEN GREATEST(admittime, TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR)) AND dischtime
           AND REGEXP_CONTAINS(med_name,
             r'(metformin|glipizide|glyburide|glimepiride|sitagliptin|linagliptin|saxagliptin|repaglinide|nateglinide|pioglitazone|rosiglitazone|acarbose|miglitol|tolbutamide|chlorpropamide)')
          THEN 1 ELSE 0 END) AS oral_final48
  FROM meds_in_admission
  GROUP BY hadm_id, subject_id, admittime, dischtime
),

-- Some admissions in cohort might have NO med events at all (no rows in meds_in_admission).
-- We should include them with zero flags so denominators are correct.
all_admissions AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime
  FROM cohort c
)

SELECT
  COUNT(a.hadm_id) AS n_admissions_in_cohort,
  SUM(COALESCE(p.insulin_first12, 0)) AS insulin_first12_count,
  ROUND(100.0 * SAFE_DIVIDE(SUM(COALESCE(p.insulin_first12, 0)), COUNT(a.hadm_id)), 2) AS insulin_first12_pct,
  SUM(COALESCE(p.insulin_final48, 0)) AS insulin_final48_count,
  ROUND(100.0 * SAFE_DIVIDE(SUM(COALESCE(p.insulin_final48, 0)), COUNT(a.hadm_id)), 2) AS insulin_final48_pct,
  ROUND(100.0 * SAFE_DIVIDE(SUM(COALESCE(p.insulin_final48, 0)), COUNT(a.hadm_id))
        - 100.0 * SAFE_DIVIDE(SUM(COALESCE(p.insulin_first12, 0)), COUNT(a.hadm_id)), 2) AS insulin_net_change_pp,
  SUM(COALESCE(p.oral_first12, 0)) AS oral_first12_count,
  ROUND(100.0 * SAFE_DIVIDE(SUM(COALESCE(p.oral_first12, 0)), COUNT(a.hadm_id)), 2) AS oral_first12_pct,
  SUM(COALESCE(p.oral_final48, 0)) AS oral_final48_count,
  ROUND(100.0 * SAFE_DIVIDE(SUM(COALESCE(p.oral_final48, 0)), COUNT(a.hadm_id)), 2) AS oral_final48_pct,
  ROUND(100.0 * SAFE_DIVIDE(SUM(COALESCE(p.oral_final48, 0)), COUNT(a.hadm_id))
        - 100.0 * SAFE_DIVIDE(SUM(COALESCE(p.oral_first12, 0)), COUNT(a.hadm_id)), 2) AS oral_net_change_pp
FROM
  all_admissions a
  LEFT JOIN per_admission_flags p
    ON a.hadm_id = p.hadm_id;