WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
),

acs_admissions AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.los
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    c.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    REGEXP_CONTAINS(LOWER(d.long_title), r'(chest pain|unstable angina|suspected mi)')
),

troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d
  ON
    l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
),

troponin_initial AS (
  SELECT
    tf.hadm_id,
    tf.troponin_value,
    CASE
      WHEN tf.troponin_value <= 0.01 THEN 'Normal'
      WHEN tf.troponin_value <= 0.04 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM
    troponin_first tf
  WHERE
    tf.rn = 1
)

SELECT
  t.troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(a.los), 2) AS avg_los_days
FROM
  acs_admissions a
JOIN
  troponin_initial t
ON
  a.hadm_id = t.hadm_id
GROUP BY
  t.troponin_category
ORDER BY
  CASE
    WHEN t.troponin_category = 'Normal' THEN 1
    WHEN t.troponin_category = 'Borderline' THEN 2
    WHEN t.troponin_category = 'Elevated' THEN 3
  END;