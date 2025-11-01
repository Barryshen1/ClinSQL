WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    -- Type 2 diabetes: ICD9 starting with 250 or ICD10 starting with E11
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
        )
    )
    -- Heart failure: ICD9 428% or ICD10 I50%
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

-- Union inpatient medication sources: prescriptions, pharmacy, emar (administration/orders)
med_orders AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    LOWER(drug) AS medname
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE hadm_id IS NOT NULL

  UNION ALL

  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    LOWER(medication) AS medname
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE hadm_id IS NOT NULL

  UNION ALL

  -- emar charttime as starttime, stoptime often not available in emar
  SELECT
    subject_id,
    hadm_id,
    charttime AS starttime,
    NULL AS stoptime,
    LOWER(medication) AS medname
  FROM `physionet-data.mimiciv_3_1_hosp.emar`
  WHERE hadm_id IS NOT NULL
),

-- Classify medication text into 'insulin' or 'oral' (common oral antidiabetic substrings)
classified AS (
  SELECT
    mo.*,
    CASE
      WHEN medname LIKE '%insulin%' THEN 'insulin'
      WHEN
        medname LIKE '%metformin%' OR
        medname LIKE '%glipizide%' OR
        medname LIKE '%glyburide%' OR
        medname LIKE '%glimepiride%' OR
        medname LIKE '%gliclazide%' OR
        medname LIKE '%sitagliptin%' OR
        medname LIKE '%saxagliptin%' OR
        medname LIKE '%linagliptin%' OR
        medname LIKE '%alogliptin%' OR
        medname LIKE '%vildagliptin%' OR
        medname LIKE '%pioglitazone%' OR
        medname LIKE '%rosiglitazone%' OR
        medname LIKE '%repaglinide%' OR
        medname LIKE '%nateglinide%' OR
        medname LIKE '%acarbose%' OR
        medname LIKE '%miglitol%' OR
        medname LIKE '%empagliflozin%' OR
        medname LIKE '%canagliflozin%' OR
        medname LIKE '%dapagliflozin%' OR
        medname LIKE '%sulfonyl%' OR
        medname LIKE '%sulphonyl%' OR
        medname LIKE '%sulfonylurea%'
      THEN 'oral'
      ELSE NULL
    END AS med_class
  FROM med_orders mo
),

-- For each hadm_id and med_class compute whether any order overlaps first24 and/or last48 windows
med_exposure AS (
  SELECT
    c.hadm_id,
    c.med_class,
    -- any overlap with first 24 hours
    MAX(
      CASE
        WHEN COALESCE(c.starttime, a.admittime) <= TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
         AND (c.stoptime IS NULL OR c.stoptime >= a.admittime)
        THEN 1 ELSE 0
      END
    ) = 1 AS in_first24,
    -- any overlap with last 48 hours (start no earlier than admittime)
    MAX(
      CASE
        WHEN COALESCE(c.starttime, a.admittime) <= a.dischtime
         AND (c.stoptime IS NULL OR c.stoptime >= GREATEST(a.admittime, TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR)))
        THEN 1 ELSE 0
      END
    ) = 1 AS in_last48
  FROM classified c
  JOIN cohort a
    ON c.hadm_id = a.hadm_id
  WHERE c.med_class IS NOT NULL
  GROUP BY c.hadm_id, c.med_class
),

-- Pivot exposures to one row per hadm with boolean flags for insulin and oral
hadm_flags AS (
  SELECT
    h.hadm_id,
    h.subject_id,
    h.admittime,
    h.dischtime,
    COALESCE((SELECT in_first24 FROM med_exposure me WHERE me.hadm_id = h.hadm_id AND me.med_class = 'insulin'), FALSE) AS insulin_first24,
    COALESCE((SELECT in_last48  FROM med_exposure me WHERE me.hadm_id = h.hadm_id AND me.med_class = 'insulin'), FALSE) AS insulin_last48,
    COALESCE((SELECT in_first24 FROM med_exposure me WHERE me.hadm_id = h.hadm_id AND me.med_class = 'oral'), FALSE) AS oral_first24,
    COALESCE((SELECT in_last48  FROM med_exposure me WHERE me.hadm_id = h.hadm_id AND me.med_class = 'oral'), FALSE) AS oral_last48
  FROM cohort h
),

cohort_size AS (
  SELECT COUNT(*) AS n FROM cohort
)

-- Final aggregated results: counts and percentages for insulin and oral
SELECT
  med_class,
  first24_count,
  ROUND(100.0 * first24_count / n, 2) AS first24_pct,
  last48_count,
  ROUND(100.0 * last48_count / n, 2) AS last48_pct,
  continued_count AS continued,
  initiated_count AS initiated,
  discontinued_count AS discontinued
FROM (
  SELECT
    'insulin' AS med_class,
    SUM(CASE WHEN insulin_first24 THEN 1 ELSE 0 END) AS first24_count,
    SUM(CASE WHEN insulin_last48 THEN 1 ELSE 0 END) AS last48_count,
    SUM(CASE WHEN insulin_first24 AND insulin_last48 THEN 1 ELSE 0 END) AS continued_count,
    SUM(CASE WHEN (NOT insulin_first24) AND insulin_last48 THEN 1 ELSE 0 END) AS initiated_count,
    SUM(CASE WHEN insulin_first24 AND (NOT insulin_last48) THEN 1 ELSE 0 END) AS discontinued_count
  FROM hadm_flags

  UNION ALL

  SELECT
    'oral' AS med_class,
    SUM(CASE WHEN oral_first24 THEN 1 ELSE 0 END) AS first24_count,
    SUM(CASE WHEN oral_last48 THEN 1 ELSE 0 END) AS last48_count,
    SUM(CASE WHEN oral_first24 AND oral_last48 THEN 1 ELSE 0 END) AS continued_count,
    SUM(CASE WHEN (NOT oral_first24) AND oral_last48 THEN 1 ELSE 0 END) AS initiated_count,
    SUM(CASE WHEN oral_first24 AND (NOT oral_last48) THEN 1 ELSE 0 END) AS discontinued_count
  FROM hadm_flags
), cohort_size cs;