WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.los
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
),

-- Identify ACS admissions
acs_admissions AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.los
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON c.hadm_id = di.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    REGEXP_CONTAINS(d.long_title, r'(?i)acute coronary syndrome')
),

-- Get first hs-TnT per admission
first_tnt AS (
  SELECT
    l.hadm_id,
    l.valuenum AS first_tnt_valuenum
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin t hs%'
    AND l.valuenum IS NOT NULL
    AND l.charttime IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) = 1
),

-- Categorize Troponin T values
tnt_categorized AS (
  SELECT
    a.hadm_id,
    a.los,
    CASE
      WHEN t.first_tnt_valuenum < 14 THEN 'Normal'
      WHEN t.first_tnt_valuenum BETWEEN 14 AND 19 THEN 'Borderline'
      WHEN t.first_tnt_valuenum >= 20 THEN 'Myocardial Injury'
      ELSE 'Unknown'
    END AS tnt_category
  FROM
    acs_admissions a
  JOIN
    first_tnt t
    ON a.hadm_id = t.hadm_id
),

-- Aggregate stats
stats AS (
  SELECT
    tnt_category,
    COUNT(*) AS patient_count,
    AVG(los) AS mean_los
  FROM
    tnt_categorized
  GROUP BY
    tnt_category
)

-- Final output with percentages
SELECT
  tnt_category,
  patient_count,
  ROUND(100.0 * patient_count / SUM(patient_count) OVER (), 2) AS percentage,
  ROUND(mean_los, 2) AS mean_los
FROM
  stats
ORDER BY
  CASE tnt_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Myocardial Injury' THEN 3
    ELSE 4
  END;