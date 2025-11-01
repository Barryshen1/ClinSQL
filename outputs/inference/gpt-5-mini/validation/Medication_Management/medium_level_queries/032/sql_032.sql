WITH
-- 1) Cohort: male inpatients age 51-61 with diabetes and acute heart failure
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- has diagnosis of diabetes
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    -- has diagnosis of acute heart failure (heuristic: heart failure + acute keyword)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
        AND LOWER(dd.long_title) LIKE '%acute%'
    )
),

-- 2) Flags for first 24 hours per hadm
first24_flags AS (
  SELECT
    c.hadm_id,
    COALESCE(MAX(
      IF(REGEXP_CONTAINS(LOWER(pr.drug), r'glargine|detemir|degludec|lantus|tresiba|levemir|basaglar'), 1, 0)
    ), 0) AS has_basal,
    COALESCE(MAX(
      IF(REGEXP_CONTAINS(LOWER(pr.drug), r'regular|lispro|aspart|glulisine|humalog|novolog|apidra|rapid'), 1, 0)
    ), 0) AS has_bolus,
    COALESCE(MAX(
      IF(REGEXP_CONTAINS(LOWER(pr.drug), r'sliding|slide|scale'), 1, 0)
    ), 0) AS has_sliding
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
    AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.hadm_id
),

-- 3) Flags for final 12 hours per hadm
final12_flags AS (
  SELECT
    c.hadm_id,
    COALESCE(MAX(
      IF(REGEXP_CONTAINS(LOWER(pr.drug), r'glargine|detemir|degludec|lantus|tresiba|levemir|basaglar'), 1, 0)
    ), 0) AS has_basal,
    COALESCE(MAX(
      IF(REGEXP_CONTAINS(LOWER(pr.drug), r'regular|lispro|aspart|glulisine|humalog|novolog|apidra|rapid'), 1, 0)
    ), 0) AS has_bolus,
    COALESCE(MAX(
      IF(REGEXP_CONTAINS(LOWER(pr.drug), r'sliding|slide|scale'), 1, 0)
    ), 0) AS has_sliding
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
    AND pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
  GROUP BY c.hadm_id
),

-- 4) Assign mutually exclusive category per hadm for each window
first24_cat AS (
  SELECT
    f.hadm_id,
    CASE
      WHEN f.has_basal = 1 AND f.has_bolus = 1 THEN 'Basal-Bolus'
      WHEN f.has_bolus = 1 AND f.has_basal = 0 AND f.has_sliding = 0 THEN 'Bolus'
      WHEN f.has_basal = 1 AND f.has_bolus = 0 AND f.has_sliding = 0 THEN 'Basal'
      WHEN f.has_sliding = 1 THEN 'Sliding-scale'
      ELSE 'None'
    END AS category
  FROM first24_flags f
),

final12_cat AS (
  SELECT
    f.hadm_id,
    CASE
      WHEN f.has_basal = 1 AND f.has_bolus = 1 THEN 'Basal-Bolus'
      WHEN f.has_bolus = 1 AND f.has_basal = 0 AND f.has_sliding = 0 THEN 'Bolus'
      WHEN f.has_basal = 1 AND f.has_bolus = 0 AND f.has_sliding = 0 THEN 'Basal'
      WHEN f.has_sliding = 1 THEN 'Sliding-scale'
      ELSE 'None'
    END AS category
  FROM final12_flags f
),

-- 5) Prepare totals and counts per category
cohort_size AS (
  SELECT COUNT(*) AS n_cohort FROM cohort
),

counts AS (
  SELECT
    cat,
    SUM(first24_count) AS first24_count,
    SUM(final12_count) AS final12_count
  FROM (
    -- first 24h counts per hadm mapped to category
    SELECT category AS cat, COUNT(*) AS first24_count, 0 AS final12_count
    FROM first24_cat
    GROUP BY category

    UNION ALL

    -- final 12h counts per hadm mapped to category
    SELECT category AS cat, 0 AS first24_count, COUNT(*) AS final12_count
    FROM final12_cat
    GROUP BY category
  )
  GROUP BY cat
)

-- Final output: only the four regimen categories requested
SELECT
  c.cat AS regimen,
  ROUND(100.0 * COALESCE(c.first24_count, 0) / cs.n_cohort, 2) AS first24_pct,
  ROUND(100.0 * COALESCE(c.final12_count, 0) / cs.n_cohort, 2) AS final12_pct,
  ROUND(100.0 * COALESCE(c.final12_count, 0) / cs.n_cohort - 100.0 * COALESCE(c.first24_count, 0) / cs.n_cohort, 2) AS pct_point_change
FROM counts c
CROSS JOIN cohort_size cs
WHERE c.cat IN ('Basal-Bolus', 'Basal', 'Bolus', 'Sliding-scale')
ORDER BY
  CASE c.cat
    WHEN 'Basal-Bolus' THEN 1
    WHEN 'Basal' THEN 2
    WHEN 'Bolus' THEN 3
    WHEN 'Sliding-scale' THEN 4
    ELSE 99
  END;