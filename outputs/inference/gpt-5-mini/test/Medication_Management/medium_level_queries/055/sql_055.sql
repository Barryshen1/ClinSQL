WITH cohort AS (
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
    AND p.anchor_age BETWEEN 39 AND 49
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    -- has T2DM (ICD-10 E11% or ICD-9 250%)
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
            (d.icd_version = 10 AND SAFE_CAST(d.icd_code AS STRING) LIKE 'E11%')
         OR (d.icd_version = 9  AND SAFE_CAST(d.icd_code AS STRING) LIKE '250%')
        )
    )
    -- has Heart Failure (ICD-10 I50% or ICD-9 428%)
    AND EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
            (d.icd_version = 10 AND SAFE_CAST(d.icd_code AS STRING) LIKE 'I50%')
         OR (d.icd_version = 9  AND SAFE_CAST(d.icd_code AS STRING) LIKE '428%')
        )
    )
),

-- Identify insulin-related prescriptions during the admission and flag their type(s).
insulin_prescriptions AS (
  SELECT
    c.hadm_id,
    pr.starttime,
    LOWER(COALESCE(pr.drug, '')) AS drug_lower,
    -- heuristic flags
    CASE
      WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%glargine%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%detemir%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%degludec%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%lantus%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%levemir%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%tresiba%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%nph%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%basal%'
      THEN 1 ELSE 0 END AS is_basal,
    CASE
      WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%lispro%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%aspart%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%glulisine%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%regular%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%humalog%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%novolog%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%bolus%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%rapid%'
      THEN 1 ELSE 0 END AS is_bolus,
    CASE
      WHEN LOWER(COALESCE(pr.drug, '')) LIKE '%sliding%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%sliding scale%' OR
           LOWER(COALESCE(pr.drug, '')) LIKE '%sliding-scale%'
      THEN 1 ELSE 0 END AS is_sliding
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON pr.hadm_id = c.hadm_id
  WHERE
    pr.starttime IS NOT NULL
    -- Only consider prescriptions that start during the admission window
    AND pr.starttime >= c.admittime
    AND pr.starttime <= c.dischtime
    -- restrict to likely insulin-related rows by coarse text match to limit data scanned
    AND (
      LOWER(COALESCE(pr.drug, '')) LIKE '%insulin%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%glargine%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%detemir%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%degludec%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%lantus%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%levemir%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%nph%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%lispro%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%aspart%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%glulisine%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%humalog%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%novolog%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%regular%'
      OR LOWER(COALESCE(pr.drug, '')) LIKE '%sliding%'
    )
),

-- For each admission, find the earliest insulin prescription starttime (first in-admission insulin)
first_insulin_start AS (
  SELECT
    ip.hadm_id,
    MIN(ip.starttime) AS first_starttime
  FROM insulin_prescriptions ip
  GROUP BY ip.hadm_id
),

-- For each admission, determine which type(s) were present at the admission-level first starttime,
-- and classify the admission's "initial regimen".
first_regimen AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    fis.first_starttime,
    -- flags whether the admission's first insulin start falls in first72h or final48h
    CASE WHEN fis.first_starttime IS NOT NULL
              AND fis.first_starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
         THEN 1 ELSE 0 END AS first_within_first72,
    CASE WHEN fis.first_starttime IS NOT NULL
              AND fis.first_starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
              AND fis.first_starttime <= c.dischtime
         THEN 1 ELSE 0 END AS first_within_final48,
    -- Determine which types appear at the first_starttime
    MAX(CASE WHEN ip.is_basal = 1 AND ip.starttime = fis.first_starttime THEN 1 ELSE 0 END) AS basal_at_first,
    MAX(CASE WHEN ip.is_bolus = 1 AND ip.starttime = fis.first_starttime THEN 1 ELSE 0 END) AS bolus_at_first,
    MAX(CASE WHEN ip.is_sliding = 1 AND ip.starttime = fis.first_starttime THEN 1 ELSE 0 END) AS sliding_at_first
  FROM
    cohort c
    LEFT JOIN first_insulin_start fis
      ON c.hadm_id = fis.hadm_id
    LEFT JOIN insulin_prescriptions ip
      ON c.hadm_id = ip.hadm_id
  GROUP BY
    c.hadm_id, c.admittime, c.dischtime, fis.first_starttime
),

-- Final classification per admission
classified_admissions AS (
  SELECT
    fr.hadm_id,
    fr.admittime,
    fr.dischtime,
    fr.first_starttime,
    fr.first_within_first72 = 1 AS first_in_first72,
    fr.first_within_final48 = 1 AS first_in_final48,
    CASE
      WHEN fr.basal_at_first = 1 AND fr.bolus_at_first = 1 THEN 'basal-bolus'
      WHEN fr.basal_at_first = 1 THEN 'basal'
      WHEN fr.bolus_at_first = 1 THEN 'bolus'
      WHEN fr.sliding_at_first = 1 THEN 'sliding-scale'
      ELSE 'none'
    END AS initial_regimen
  FROM first_regimen fr
)

-- Aggregate counts and percentages by regimen (for the four regimens requested)
SELECT
  r.regimen AS regimen,
  COALESCE(SUM(CASE WHEN ca.initial_regimen = r.regimen AND ca.first_in_first72 THEN 1 ELSE 0 END), 0) AS n_first72,
  ROUND(
    100.0 * COALESCE(SUM(CASE WHEN ca.initial_regimen = r.regimen AND ca.first_in_first72 THEN 1 ELSE 0 END), 0)
    / GREATEST((SELECT COUNT(*) FROM cohort), 1), 2
  ) AS pct_first72,
  COALESCE(SUM(CASE WHEN ca.initial_regimen = r.regimen AND ca.first_in_final48 THEN 1 ELSE 0 END), 0) AS n_final48,
  ROUND(
    100.0 * COALESCE(SUM(CASE WHEN ca.initial_regimen = r.regimen AND ca.first_in_final48 THEN 1 ELSE 0 END), 0)
    / GREATEST((SELECT COUNT(*) FROM cohort), 1), 2
  ) AS pct_final48,
  ROUND(
    ABS(
      -- difference in percentage points
      (100.0 * COALESCE(SUM(CASE WHEN ca.initial_regimen = r.regimen AND ca.first_in_final48 THEN 1 ELSE 0 END), 0)
       / GREATEST((SELECT COUNT(*) FROM cohort), 1))
      -
      (100.0 * COALESCE(SUM(CASE WHEN ca.initial_regimen = r.regimen AND ca.first_in_first72 THEN 1 ELSE 0 END), 0)
       / GREATEST((SELECT COUNT(*) FROM cohort), 1))
    ), 2
  ) AS abs_pct_point_diff
FROM
  -- ensure rows for the four regimens even if zero counts
  UNNEST([STRUCT('basal' AS regimen),
          STRUCT('bolus' AS regimen),
          STRUCT('basal-bolus' AS regimen),
          STRUCT('sliding-scale' AS regimen)]) AS r
LEFT JOIN classified_admissions ca
  ON ca.initial_regimen = r.regimen
GROUP BY r.regimen
ORDER BY
  CASE r.regimen
    WHEN 'basal' THEN 1
    WHEN 'bolus' THEN 2
    WHEN 'basal-bolus' THEN 3
    WHEN 'sliding-scale' THEN 4
    ELSE 5 END;