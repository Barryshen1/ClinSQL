WITH troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value,
    CASE
      WHEN l.valuenum <= 0.01 THEN 'Normal'
      WHEN l.valuenum <= 0.039 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
),
admissions_with_troponin AS (
  SELECT
    t.hadm_id,
    t.troponin_value,
    t.troponin_category
  FROM
    troponin_first AS t
  WHERE
    t.rn = 1
),
acs_admissions AS (
  SELECT DISTINCT
    di.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS di
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    d.icd_code = 'R074' -- ICD-10 for Chest pain, unspecified
),
eligible_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients AS p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
),
final_cohort AS (
  SELECT
    e.hadm_id,
    t.troponin_value,
    t.troponin_category
  FROM
    eligible_patients AS e
  INNER JOIN
    admissions_with_troponin AS t
    ON e.hadm_id = t.hadm_id
  INNER JOIN
    acs_admissions AS acs
    ON e.hadm_id = acs.hadm_id
)
SELECT
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  AVG(troponin_value) AS mean_troponin,
  APPROX_QUANTILES(troponin_value, 2)[OFFSET(1)] AS median_troponin,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)] - APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)] AS iqr
FROM
  final_cohort
GROUP BY
  troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;