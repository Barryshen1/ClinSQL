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
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),
t2 AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%type 2 diabetes%'
),
hf AS (
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%heart failure%'
),
cohort2 AS (
  SELECT
    c.*
  FROM
    cohort c
  WHERE
    c.hadm_id IN (SELECT hadm_id FROM t2)
    AND c.hadm_id IN (SELECT hadm_id FROM hf)
),
glp_flags AS (
  SELECT
    c.hadm_id,
    MAX(CASE
      WHEN pr.starttime BETWEEN c.admittime 
                            AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
      THEN 1 ELSE 0 END) AS first72_flag,
    MAX(CASE
      WHEN pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
                            AND c.dischtime
      THEN 1 ELSE 0 END) AS last12_flag
  FROM
    cohort2 c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON pr.hadm_id = c.hadm_id
      AND (
        LOWER(pr.drug) LIKE '%exenatide%'
        OR LOWER(pr.drug) LIKE '%liraglutide%'
        OR LOWER(pr.drug) LIKE '%dulaglutide%'
        OR LOWER(pr.drug) LIKE '%semaglutide%'
        OR LOWER(pr.drug) LIKE '%lixisenatide%'
      )
  GROUP BY
    c.hadm_id
)
SELECT
  COUNT(1) AS total_admissions,
  SUM(first72_flag) AS n_started_first72h,
  SUM(last12_flag) AS n_started_last12h,
  ROUND(100.0 * SUM(first72_flag) / COUNT(1), 2) AS pct_first72h,
  ROUND(100.0 * SUM(last12_flag) / COUNT(1), 2) AS pct_last12h,
  ROUND(ABS(
    100.0 * SUM(first72_flag) / COUNT(1)
    - 100.0 * SUM(last12_flag) / COUNT(1)
  ), 2) AS abs_diff_percentage_points
FROM
  glp_flags;