WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

diabetes_hf_admissions AS (
  SELECT DISTINCT
    c.hadm_id
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code
    AND d.icd_version = dd.icd_version
  WHERE
    (dd.icd_code LIKE 'E11%' OR dd.icd_code LIKE 'I50%')
),

glp1_drugs AS (
  SELECT
    hadm_id,
    starttime,
    drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) IN (
      'exenatide', 'liraglutide', 'dulaglutide', 'semaglutide', 'lixisenatide'
    )
    AND hadm_id IS NOT NULL
),

admissions_with_glp1_first72h AS (
  SELECT DISTINCT
    c.hadm_id
  FROM
    cohort c
  JOIN
    glp1_drugs g
  ON
    c.hadm_id = g.hadm_id
  WHERE
    g.starttime >= c.admittime
    AND g.starttime <= DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
),

admissions_with_glp1_last12h AS (
  SELECT DISTINCT
    c.hadm_id
  FROM
    cohort c
  JOIN
    glp1_drugs g
  ON
    c.hadm_id = g.hadm_id
  WHERE
    g.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
    AND g.starttime <= c.dischtime
),

denominator AS (
  SELECT
    c.hadm_id
  FROM
    cohort c
  JOIN
    diabetes_hf_admissions d
  ON
    c.hadm_id = d.hadm_id
)

SELECT
  ROUND(100 * COUNT(DISTINCT f72.hadm_id) / COUNT(DISTINCT d.hadm_id), 2) AS pct_first72h,
  ROUND(100 * COUNT(DISTINCT l12.hadm_id) / COUNT(DISTINCT d.hadm_id), 2) AS pct_last12h,
  ROUND(100 * (
    COUNT(DISTINCT f72.hadm_id) / COUNT(DISTINCT d.hadm_id) -
    COUNT(DISTINCT l12.hadm_id) / COUNT(DISTINCT d.hadm_id)
  ), 2) AS abs_diff_pp
FROM
  denominator d
LEFT JOIN
  admissions_with_glp1_first72h f72
ON
  d.hadm_id = f72.hadm_id
LEFT JOIN
  admissions_with_glp1_last12h l12
ON
  d.hadm_id = l12.hadm_id;