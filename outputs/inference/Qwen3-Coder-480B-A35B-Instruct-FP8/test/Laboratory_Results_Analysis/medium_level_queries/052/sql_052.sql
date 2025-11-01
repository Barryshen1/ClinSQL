WITH ami_admissions AS (
  -- Identify admissions with AMI diagnosis
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute myocardial infarction%'
),

eligible_patients AS (
  -- Filter male patients aged 76–86 at admission
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.anchor_year,
    a.admittime,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    ami_admissions a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 76 AND 86
),

troponin_first AS (
  -- Get first Troponin I lab per admission
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
      ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) LIKE '%troponin i%'
    AND l.valuenum IS NOT NULL
    AND l.charttime >= (
      SELECT admittime
      FROM physionet-data.mimiciv_3_1_hosp.admissions a
      WHERE a.hadm_id = l.hadm_id
    )
),

first_troponin AS (
  -- Select only first labs
  SELECT
    hadm_id,
    troponin_value
  FROM
    troponin_first
  WHERE
    rn = 1
),

categorized AS (
  -- Categorize Troponin I values
  SELECT
    hadm_id,
    troponin_value,
    CASE
      WHEN troponin_value <= 0.04 THEN 'Normal'
      WHEN troponin_value <= 0.40 THEN 'Borderline'
      ELSE 'Elevated'
    END AS category
  FROM
    first_troponin
)

-- Final aggregation
SELECT
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM
  categorized
GROUP BY
  category

UNION ALL

SELECT
  'Overall Mean' AS category,
  ROUND(AVG(troponin_value), 4) AS count,
  NULL AS percentage
FROM
  first_troponin

UNION ALL

SELECT
  'Overall Median' AS category,
  ROUND(APPROX_QUANTILES(troponin_value, 2)[OFFSET(1)], 4) AS count,
  NULL AS percentage
FROM
  first_troponin

UNION ALL

SELECT
  'Overall IQR' AS category,
  ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)], 4) AS count,
  ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)], 4) AS percentage
FROM
  first_troponin
ORDER BY
  category;