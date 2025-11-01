WITH
-- Identify diagnosis codes / descriptions consistent with T2DM and heart failure
diag_with_text AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version,
    LOWER(COALESCE(dic.long_title, '')) AS long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
  ON d.icd_code = dic.icd_code AND d.icd_version = dic.icd_version
),

-- Admissions meeting diagnosis criteria: each hadm_id must have BOTH T2DM and HF diagnosis records
hadm_with_dx AS (
  SELECT hadm_id
  FROM (
    SELECT hadm_id,
      MAX(CASE
            WHEN (
              (icd_version = 10 AND STARTS_WITH(icd_code, 'E11')) -- ICD-10 type 2 diabetes
              OR long_title LIKE '%type 2%'
              OR long_title LIKE '%type ii%'
              OR long_title LIKE '%diabetes mellitus%' -- broad capture
            ) THEN 1 ELSE 0 END) AS has_dm2,
      MAX(CASE
            WHEN (
              (icd_version = 10 AND STARTS_WITH(icd_code, 'I50')) -- ICD-10 heart failure
              OR (icd_version = 9 AND STARTS_WITH(icd_code, '428')) -- ICD-9 heart failure
              OR long_title LIKE '%heart failure%'
            ) THEN 1 ELSE 0 END) AS has_hf
    FROM diag_with_text
    GROUP BY hadm_id
  ) AS dx_flags
  WHERE has_dm2 = 1 AND has_hf = 1
),

-- Cohort: male patients age 63-73 with an admission that meets diagnosis criteria
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  JOIN
    hadm_with_dx h
  ON a.hadm_id = h.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    -- ensure admission times exist
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Union inpatient medication orders/dispenses from prescriptions and pharmacy
meds_raw AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    drug,
    route
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IS NOT NULL

  UNION ALL

  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    medication AS drug,
    route
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE hadm_id IS NOT NULL
),

-- Classify med records as insulin and/or oral agents based on drug text
meds_classified AS (
  SELECT
    m.*,
    LOWER(COALESCE(m.drug, '')) AS drug_l,
    -- insulin pattern: common insulin names and the word 'insulin'
    REGEXP_CONTAINS(LOWER(COALESCE(m.drug, '')),
      r'(insulin|lispro|aspart|glargine|detemir|tresiba|humalog|humulin|novolog|lantus|levemir|novolin)'
    ) AS is_insulin,
    -- oral antihyperglycemics: metformin, sulfonylureas, DPP4, SGLT2, TZD, meglitinides, alpha-glucosidase inhibitors, generic 'oral'
    REGEXP_CONTAINS(LOWER(COALESCE(m.drug, '')),
      r'(metformin|glipizide|glimepiride|glyburide|gliclazide|sitagliptin|saxagliptin|linagliptin|alogliptin|vildagliptin|canagliflozin|dapagliflozin|empagliflozin|pioglitazone|rosiglitazone|repaglinide|nateglinide|acarbose|miglitol|sulfonylurea|sulfonylureas|sulfonyl|dipeptidyl peptidase|ddp4|dpp-4|oral)'
    ) AS is_oral
  FROM meds_raw m
),

-- Restrict meds to the cohort's admissions and compute overlaps with first and final 24h windows
meds_overlap AS (
  SELECT
    c.hadm_id,
    mc.is_insulin,
    mc.is_oral,
    mc.starttime,
    mc.stoptime,
    c.admittime,
    c.dischtime,
    -- flags whether this med record overlaps the first 24h window
    (mc.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
     AND (mc.stoptime IS NULL OR mc.stoptime >= c.admittime)
    ) AS overlaps_first24,
    -- flags whether this med record overlaps the final 24h window
    (mc.starttime <= c.dischtime
     AND (mc.stoptime IS NULL OR mc.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR))
    ) AS overlaps_final24
  FROM
    cohort c
  LEFT JOIN
    meds_classified mc
  ON c.hadm_id = mc.hadm_id
  -- Only consider records with non-null drug text and at least one classification hit
  WHERE
    mc.drug IS NOT NULL
    AND (mc.is_insulin OR mc.is_oral)
),

-- Per-admission flags: whether any insulin / any oral agent is present in first and final 24h
hadm_flags AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    -- if there are no med records for this admission, the boolean should be FALSE
    COALESCE(MAX(CASE WHEN mo.is_insulin AND mo.overlaps_first24 THEN 1 ELSE 0 END), 0) = 1 AS insulin_first24,
    COALESCE(MAX(CASE WHEN mo.is_insulin AND mo.overlaps_final24 THEN 1 ELSE 0 END), 0) = 1 AS insulin_final24,
    COALESCE(MAX(CASE WHEN mo.is_oral AND mo.overlaps_first24 THEN 1 ELSE 0 END), 0) = 1 AS oral_first24,
    COALESCE(MAX(CASE WHEN mo.is_oral AND mo.overlaps_final24 THEN 1 ELSE 0 END), 0) = 1 AS oral_final24
  FROM
    cohort h
  LEFT JOIN
    meds_overlap mo
  ON h.hadm_id = mo.hadm_id
  GROUP BY
    h.hadm_id, h.subject_id, h.admittime, h.dischtime
)

-- Final aggregation: counts, percentages, and percentage-point changes
SELECT
  COUNT(1) AS total_admissions,
  -- Insulin
  SUM(CASE WHEN insulin_first24 THEN 1 ELSE 0 END) AS insulin_first24_count,
  ROUND(100.0 * SUM(CASE WHEN insulin_first24 THEN 1 ELSE 0 END) / COUNT(1), 2) AS insulin_first24_pct,
  SUM(CASE WHEN insulin_final24 THEN 1 ELSE 0 END) AS insulin_final24_count,
  ROUND(100.0 * SUM(CASE WHEN insulin_final24 THEN 1 ELSE 0 END) / COUNT(1), 2) AS insulin_final24_pct,
  ROUND(
    100.0 * SUM(CASE WHEN insulin_final24 THEN 1 ELSE 0 END) / COUNT(1)
    - 100.0 * SUM(CASE WHEN insulin_first24 THEN 1 ELSE 0 END) / COUNT(1)
  , 2) AS insulin_pct_point_change,
  -- Oral agents
  SUM(CASE WHEN oral_first24 THEN 1 ELSE 0 END) AS oral_first24_count,
  ROUND(100.0 * SUM(CASE WHEN oral_first24 THEN 1 ELSE 0 END) / COUNT(1), 2) AS oral_first24_pct,
  SUM(CASE WHEN oral_final24 THEN 1 ELSE 0 END) AS oral_final24_count,
  ROUND(100.0 * SUM(CASE WHEN oral_final24 THEN 1 ELSE 0 END) / COUNT(1), 2) AS oral_final24_pct,
  ROUND(
    100.0 * SUM(CASE WHEN oral_final24 THEN 1 ELSE 0 END) / COUNT(1)
    - 100.0 * SUM(CASE WHEN oral_first24 THEN 1 ELSE 0 END) / COUNT(1)
  , 2) AS oral_pct_point_change
FROM
  hadm_flags;