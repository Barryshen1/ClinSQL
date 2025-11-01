WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd
      WHERE icd_code LIKE 'E11%' AND icd_version = 10
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd
      WHERE icd_code LIKE 'I50%' AND icd_version = 10
    )
),

glp1_initiations AS (
  SELECT
    c.hadm_id,
    MIN(pr.starttime) AS first_glp1_time
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON c.hadm_id = pr.hadm_id
  WHERE
    LOWER(pr.drug) IN (
      'semaglutide', 'liraglutide', 'dulaglutide', 'exenatide',
      'lixisenatide', 'albiglutide'
    )
    AND pr.starttime IS NOT NULL
  GROUP BY
    c.hadm_id
),

initiation_flags AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN g.first_glp1_time BETWEEN c.admittime AND c.admittime + INTERVAL 12 HOUR THEN 1
      ELSE 0
    END AS initiated_early,
    CASE
      WHEN g.first_glp1_time BETWEEN c.dischtime - INTERVAL 24 HOUR AND c.dischtime THEN 1
      ELSE 0
    END AS initiated_late
  FROM
    cohort c
  LEFT JOIN
    glp1_initiations g
    ON c.hadm_id = g.hadm_id
)

SELECT
  ROUND(
    100 * SUM(initiated_early) / COUNT(*),
    2
  ) AS percent_early_initiation,
  ROUND(
    100 * SUM(initiated_late) / COUNT(*),
    2
  ) AS percent_late_initiation,
  ROUND(
    100 * SUM(initiated_early) / COUNT(*) - 100 * SUM(initiated_late) / COUNT(*),
    2
  ) AS net_percentage_point_change
FROM
  initiation_flags;