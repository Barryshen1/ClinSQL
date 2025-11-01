WITH
  -- Step 1: Identify index admissions for female patients aged 87-97
  index_admissions AS (
    SELECT
      subject_id,
      hadm_id,
      admittime,
      anchor_age
    FROM (
      SELECT
        p.subject_id,
        a.hadm_id,
        a.admittime,
        p.anchor_age,
        ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS rn
      FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
      JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
      WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 87 AND 97
    )
    WHERE rn = 1
  ),
  -- Step 2: Filter admissions with chest pain diagnosis
  chest_pain_admissions AS (
    SELECT
      ia.subject_id,
      ia.hadm_id
    FROM
      index_admissions ia
    JOIN
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON ia.hadm_id = di.hadm_id
    JOIN
      `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code
      AND di.icd_version = d.icd_version
    WHERE
      LOWER(d.long_title) LIKE '%chest pain%'
  ),
  -- Step 3: Identify hs-TnT itemid (using d_labitems) - removed valueuom condition
  hs_tnt_itemid AS (
    SELECT
      itemid
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE
      LOWER(label) LIKE '%hs-tnt%'
    LIMIT 1  -- Use one itemid if multiple exist
  ),
  -- Step 4: Get first hs-TnT test per admission - added unit filter
  first_hstnt AS (
    SELECT
      cpa.subject_id,
      cpa.hadm_id,
      le.valuenum AS hs_tnt_value
    FROM
      chest_pain_admissions cpa
    JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON cpa.hadm_id = le.hadm_id
    WHERE
      le.itemid = (SELECT itemid FROM hs_tnt_itemid)
      AND le.valuenum IS NOT NULL  -- Exclude non-numeric values
      AND LOWER(le.valueuom) = 'ng/ml'  -- Ensure unit is ng/mL (case-insensitive)
    QUALIFY
      ROW_NUMBER() OVER (PARTITION BY cpa.hadm_id ORDER BY le.charttime) = 1
  ),
  -- Step 5: Categorize hs-TnT values
  categorized AS (
    SELECT
      subject_id,
      hadm_id,
      hs_tnt_value,
      CASE
        WHEN hs_tnt_value <= 0.04 THEN 'Normal'
        WHEN hs_tnt_value > 0.04 AND hs_tnt_value <= 0.1 THEN 'Borderline'
        WHEN hs_tnt_value > 0.1 THEN 'Injury'
        ELSE 'Unknown'  -- Safety for unexpected values
      END AS category
    FROM
      first_hstnt
  ),
  -- Step 6: Aggregate by category
  aggregated AS (
    SELECT
      category,
      COUNT(*) AS count,
      COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage,
      AVG(hs_tnt_value) AS mean,
      APPROX_QUANTILES(hs_tnt_value, 100)[OFFSET(50)] AS median,
      APPROX_QUANTILES(hs_tnt_value, 100)[OFFSET(75)] - APPROX_QUANTILES(hs_tnt_value, 100)[OFFSET(25)] AS iqr
    FROM
      categorized
    GROUP BY
      category
  )
SELECT
  category,
  count,
  ROUND(percentage, 2) AS percentage,  -- Round percentage to 2 decimals
  ROUND(mean, 4) AS mean,              -- Round mean to 4 decimals
  ROUND(median, 4) AS median,          -- Round median to 4 decimals
  ROUND(iqr, 4) AS iqr                 -- Round IQR to 4 decimals
FROM
  aggregated
ORDER BY
  category;