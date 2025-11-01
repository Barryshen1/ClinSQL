WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 57 AND 67
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE
        (dd.icd_code LIKE 'E10%' OR dd.icd_code LIKE 'E11%' OR dd.icd_code LIKE '250%')
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE
        (dd.icd_code LIKE 'I50%' OR dd.icd_code LIKE '428%')
    )
),

glp1_prescriptions AS (
  SELECT
    c.hadm_id,
    CASE WHEN pr.starttime BETWEEN c.admittime AND c.admittime + INTERVAL 48 HOUR THEN 1 ELSE 0 END AS in_first_48h,
    CASE WHEN pr.starttime BETWEEN c.dischtime - INTERVAL 12 HOUR AND c.dischtime THEN 1 ELSE 0 END AS in_last_12h
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
  ON
    c.hadm_id = pr.hadm_id
  WHERE
    LOWER(pr.drug) LIKE '%semaglutide%'
    OR LOWER(pr.drug) LIKE '%liraglutide%'
    OR LOWER(pr.drug) LIKE '%dulaglutide%'
    OR LOWER(pr.drug) LIKE '%exenatide%'
    OR LOWER(pr.drug) LIKE '%lixisenatide%'
),

prescribed_flags AS (
  SELECT
    hadm_id,
    MAX(in_first_48h) AS first_48h_flag,
    MAX(in_last_12h) AS last_12h_flag
  FROM
    glp1_prescriptions
  GROUP BY
    hadm_id
),

counts AS (
  SELECT
    COUNT(*) AS total_patients,
    SUM(first_48h_flag) AS first_48h_count,
    SUM(last_12h_flag) AS last_12h_count
  FROM
    cohort c
  LEFT JOIN
    prescribed_flags p
  ON
    c.hadm_id = p.hadm_id
)

SELECT
  total_patients,
  first_48h_count,
  last_12h_count,
  ROUND(100 * first_48h_count / total_patients, 2) AS first_48h_prevalence_pct,
  ROUND(100 * last_12h_count / total_patients, 2) AS last_12h_prevalence_pct,
  ROUND(100 * (last_12h_count - first_48h_count) / total_patients, 2) AS abs_change_pct,
  CASE
    WHEN first_48h_count = 0 THEN NULL
    ELSE ROUND(100 * (last_12h_count - first_48h_count) / first_48h_count, 2)
  END AS rel_change_pct
FROM
  counts;