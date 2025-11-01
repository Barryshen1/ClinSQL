WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 41 AND 51
),

-- Diagnoses: chest pain or AMI (ICD-9 and ICD-10)
diagnosis_filtered AS (
  SELECT DISTINCT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.age_at_admission
  FROM
    patient_admissions pa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    pa.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%chest pain%'
    OR LOWER(d.long_title) LIKE '%myocardial infarction%'
    OR LOWER(d.long_title) LIKE '%acute mi%'
    OR (d.icd_version = 9 AND d.icd_code LIKE '410%')
    OR (d.icd_version = 10 AND d.icd_code = 'I21.9')
    OR (d.icd_version = 9 AND d.icd_code IN ('786.50', '786.59'))
    OR (d.icd_version = 10 AND d.icd_code = 'R07.9')
),

-- Get Troponin T lab events
troponin_lab AS (
  SELECT
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
  ON
    le.itemid = dli.itemid
  WHERE
    LOWER(dli.label) = 'troponin t'
    AND le.valuenum IS NOT NULL
    AND le.charttime IS NOT NULL
),

-- First Troponin T per admission
first_troponin AS (
  SELECT
    hadm_id,
    valuenum AS first_troponin_t
  FROM
    troponin_lab
  WHERE
    rn = 1
),

-- Combine with diagnosis-filtered admissions and categorize
categorized AS (
  SELECT
    df.hadm_id,
    df.age_at_admission,
    ft.first_troponin_t,
    CASE
      WHEN ft.first_troponin_t <= 0.014 THEN 'normal'
      WHEN ft.first_troponin_t <= 0.050 THEN 'borderline'
      ELSE 'elevated'
    END AS troponin_category
  FROM
    diagnosis_filtered df
  JOIN
    first_troponin ft
  ON
    df.hadm_id = ft.hadm_id
),

-- Compute percentiles using window functions
percentiles AS (
  SELECT
    troponin_category,
    first_troponin_t,
    PERCENTILE_CONT(first_troponin_t, 0.25) OVER (PARTITION BY troponin_category) AS p25,
    PERCENTILE_CONT(first_troponin_t, 0.5) OVER (PARTITION BY troponin_category) AS p50,
    PERCENTILE_CONT(first_troponin_t, 0.75) OVER (PARTITION BY troponin_category) AS p75
  FROM
    categorized
)

-- Final aggregation
SELECT
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(first_troponin_t), 4) AS mean_troponin_t,
  ROUND(ANY_VALUE(p50), 4) AS median_troponin_t,
  CONCAT(
    ROUND(ANY_VALUE(p25), 4),
    ' – ',
    ROUND(ANY_VALUE(p75), 4)
  ) AS iqr_troponin_t
FROM
  percentiles
GROUP BY
  troponin_category
ORDER BY
  troponin_category;