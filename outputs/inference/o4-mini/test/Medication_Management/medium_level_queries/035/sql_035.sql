WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
),
dx_diabetes AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
      AND d.icd_version = dicd.icd_version
  WHERE
    LOWER(dicd.long_title) LIKE '%diabetes%'
),
dx_hf AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
      AND d.icd_version = dicd.icd_version
  WHERE
    LOWER(dicd.long_title) LIKE '%heart failure%'
),
cohort_dx AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM
    cohort c
    JOIN dx_diabetes dd
      ON c.subject_id = dd.subject_id
      AND c.hadm_id = dd.hadm_id
    JOIN dx_hf dh
      ON c.subject_id = dh.subject_id
      AND c.hadm_id = dh.hadm_id
),
glp1_pres AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE
    LOWER(p.drug) LIKE '%exenatide%'
    OR LOWER(p.drug) LIKE '%liraglutide%'
    OR LOWER(p.drug) LIKE '%dulaglutide%'
    OR LOWER(p.drug) LIKE '%semaglutide%'
    OR LOWER(p.drug) LIKE '%lixisenatide%'
    OR LOWER(p.drug) LIKE '%albiglutide%'
),
flags AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN gp.starttime BETWEEN c.admittime
                              AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS has_48h,
    MAX(CASE WHEN gp.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
                              AND c.dischtime
             THEN 1 ELSE 0 END) AS has_final12h
  FROM
    cohort_dx c
    LEFT JOIN glp1_pres gp
      ON c.subject_id = gp.subject_id
      AND c.hadm_id = gp.hadm_id
  GROUP BY
    c.hadm_id
)
SELECT
  COUNT(1) AS total_admissions,
  SUM(has_48h) AS n_48h,
  SUM(has_final12h) AS n_final12h,
  ROUND(100.0 * SUM(has_48h) / COUNT(1), 2) AS pct_48h,
  ROUND(100.0 * SUM(has_final12h) / COUNT(1), 2) AS pct_final12h,
  ROUND(
    ROUND(100.0 * SUM(has_final12h) / COUNT(1), 2)
    - ROUND(100.0 * SUM(has_48h) / COUNT(1), 2)
  , 2) AS abs_change_pct,
  ROUND(
    CASE
      WHEN SUM(has_48h) = 0 THEN NULL
      ELSE
        100.0 * (
          (SUM(has_final12h) * 1.0 / COUNT(1))
          - (SUM(has_48h) * 1.0 / COUNT(1))
        )
        / (SUM(has_48h) * 1.0 / COUNT(1))
    END
  , 2) AS rel_change_pct
FROM
  flags;