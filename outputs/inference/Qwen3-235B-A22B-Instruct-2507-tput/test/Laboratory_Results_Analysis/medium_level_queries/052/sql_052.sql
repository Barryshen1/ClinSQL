WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    AND a.admittime IS NOT NULL
),
ami_admissions AS (
  SELECT DISTINCT pa.subject_id, pa.hadm_id, pa.admittime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE pa.age_at_admit BETWEEN 76 AND 86
    AND (
      (di.icd_version = 9 AND di.icd_code LIKE '410%')
      OR (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%' OR di.icd_code LIKE 'I23%'))
    )
),
trop_i_lab AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp`.d_labitems
  WHERE LOWER(label) = 'troponin i'
),
first_trop_i AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN trop_i_lab t ON le.itemid = t.itemid
  INNER JOIN ami_admissions am ON le.hadm_id = am.hadm_id
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= am.admittime
),
first_trop_i_filtered AS (
  SELECT valuenum
  FROM first_trop_i
  WHERE rn = 1
),
categorized AS (
  SELECT
    valuenum,
    CASE
      WHEN valuenum <= 0.04 THEN 'Normal'
      WHEN valuenum > 0.04 AND valuenum < 0.40 THEN 'Borderline'
      WHEN valuenum >= 0.40 THEN 'Elevated'
      ELSE 'Unknown'
    END AS category
  FROM first_trop_i_filtered
),
summary_stats AS (
  SELECT
    category,
    COUNT(*) AS count
  FROM categorized
  GROUP BY category
),
total_count AS (
  SELECT SUM(count) AS total FROM summary_stats
),
percentages AS (
  SELECT
    s.category,
    s.count,
    ROUND(s.count * 100.0 / t.total, 2) AS percentage
  FROM summary_stats s
  CROSS JOIN total_count t
),
overall_stats AS (
  SELECT
    ROUND(AVG(valuenum) OVER (), 3) AS mean_trop_i,
    ROUND(PERCENTILE_CONT(valuenum, 0.5) OVER (), 3) AS median_trop_i,
    ROUND(PERCENTILE_CONT(valuenum, 0.25) OVER (), 3) AS q1,
    ROUND(PERCENTILE_CONT(valuenum, 0.75) OVER (), 3) AS q3
  FROM first_trop_i_filtered
  LIMIT 1
)
SELECT
  p.category,
  p.count,
  p.percentage,
  o.mean_trop_i,
  o.median_trop_i,
  o.q1 AS iqr_q1,
  o.q3 AS iqr_q3,
  CONCAT(o.q1, ' - ', o.q3) AS iqr_range
FROM percentages p
CROSS JOIN overall_stats o
ORDER BY p.category;