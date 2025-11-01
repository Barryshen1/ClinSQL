WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  WHERE
    p.gender = 'F'
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
      OR
      (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
    )
),
filtered_cohort AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM cohort
  WHERE age_at_admission BETWEEN 40 AND 50
),
first_troponin AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    l.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN filtered_cohort fc
    ON l.hadm_id = fc.hadm_id
  WHERE
    l.itemid = 51003  -- Troponin T itemid
    AND l.valuenum IS NOT NULL
),
troponin_data AS (
  SELECT
    hadm_id,
    valuenum,
    COALESCE(SAFE_CAST(ref_range_upper AS FLOAT64), 0.01) AS ref_range_upper  -- Cast to numeric, default to 0.01
  FROM first_troponin
  WHERE rn = 1
),
categorized AS (
  SELECT
    hadm_id,
    CASE
      WHEN valuenum <= ref_range_upper THEN 'normal'
      WHEN valuenum <= (ref_range_upper * 1.5) THEN 'borderline'
      ELSE 'elevated'
    END AS category
  FROM troponin_data
)
SELECT
  category,
  COUNT(*) AS count
FROM categorized
GROUP BY category
ORDER BY category;