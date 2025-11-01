WITH troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
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
    LOWER(d.long_title) LIKE '%acute coronary%'
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
filtered_labs AS (
  SELECT
    tf.hadm_id,
    tf.valuenum
  FROM
    troponin_first AS tf
  INNER JOIN
    acs_admissions AS aa
    ON tf.hadm_id = aa.hadm_id
  INNER JOIN
    eligible_patients AS ep
    ON tf.hadm_id = ep.hadm_id
  WHERE
    tf.rn = 1
),
categorized AS (
  SELECT
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum <= 0.01 THEN 'Normal'
      WHEN valuenum > 0.01 AND valuenum <= 0.04 THEN 'Borderline'
      WHEN valuenum > 0.04 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM
    filtered_labs
)
SELECT
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM
  categorized
GROUP BY
  troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;