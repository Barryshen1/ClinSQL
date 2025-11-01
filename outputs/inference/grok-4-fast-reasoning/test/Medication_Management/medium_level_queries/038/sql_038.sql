WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E1[0-4]%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '250.%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),
glp_admins AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  INNER JOIN cohort c
    ON e.subject_id = c.subject_id
    AND e.hadm_id = c.hadm_id
  WHERE e.charttime >= c.admittime
    AND e.charttime < c.dischtime
    AND (
      LOWER(e.medication) LIKE '%liraglutide%'
      OR LOWER(e.medication) LIKE '%semaglutide%'
      OR LOWER(e.medication) LIKE '%dulaglutide%'
      OR LOWER(e.medication) LIKE '%exenatide%'
      OR LOWER(e.medication) LIKE '%albiglutide%'
      OR LOWER(e.medication) LIKE '%lixisenatide%'
      OR LOWER(e.medication) LIKE '%victoza%'
      OR LOWER(e.medication) LIKE '%ozempic%'
      OR LOWER(e.medication) LIKE '%trulicity%'
      OR LOWER(e.medication) LIKE '%byetta%'
      OR LOWER(e.medication) LIKE '%bydureon%'
      OR LOWER(e.medication) LIKE '%saxenda%'
      OR LOWER(e.medication) LIKE '%rybelsus%'
      OR LOWER(e.medication) LIKE '%adlyxin%'
    )
),
first_admin AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_time
  FROM glp_admins
  GROUP BY subject_id, hadm_id
),
cohort_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    fa.first_time,
    EXISTS (
      SELECT 1
      FROM glp_admins g
      WHERE g.subject_id = c.subject_id
        AND g.hadm_id = c.hadm_id
        AND g.charttime >= c.admittime
        AND g.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    ) AS has_first72,
    (fa.first_time IS NOT NULL
     AND fa.first_time >= c.admittime
     AND fa.first_time < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)) AS init_first72,
    EXISTS (
      SELECT 1
      FROM glp_admins g
      WHERE g.subject_id = c.subject_id
        AND g.hadm_id = c.hadm_id
        AND g.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
        AND g.charttime < c.dischtime
    ) AS has_final24,
    (fa.first_time IS NOT NULL
     AND fa.first_time >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
     AND fa.first_time < c.dischtime) AS init_final24
  FROM cohort c
  LEFT JOIN first_admin fa
    ON c.subject_id = fa.subject_id
    AND c.hadm_id = fa.hadm_id
),
agg AS (
  SELECT
    COUNT(*) AS total_n,
    SUM(CAST(has_first72 AS INT64)) AS prev1_n,
    SUM(CAST(init_first72 AS INT64)) AS init1_n,
    SUM(CAST(has_final24 AS INT64)) AS prev2_n,
    SUM(CAST(init_final24 AS INT64)) AS init2_n
  FROM cohort_flags
)
SELECT
  total_n,
  ROUND(100.0 * prev1_n / total_n, 2) AS prevalence_first72_pct,
  ROUND(100.0 * init1_n / total_n, 2) AS initiation_first72_pct,
  ROUND(100.0 * prev2_n / total_n, 2) AS prevalence_final24_pct,
  ROUND(100.0 * init2_n / total_n, 2) AS initiation_final24_pct,
  ROUND(100.0 * prev2_n / total_n - 100.0 * prev1_n / total_n, 2) AS abs_change_prevalence,
  CASE
    WHEN prev1_n > 0 THEN ROUND((prev2_n - prev1_n) * 100.0 / prev1_n, 2)
    ELSE NULL
  END AS rel_change_prevalence_pct,
  ROUND(100.0 * init2_n / total_n - 100.0 * init1_n / total_n, 2) AS abs_change_initiation,
  CASE
    WHEN init1_n > 0 THEN ROUND((init2_n - init1_n) * 100.0 / init1_n, 2)
    ELSE NULL
  END AS rel_change_initiation_pct
FROM agg;