WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
  ON
    a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          dd.icd_code LIKE 'E10%' OR dd.icd_code LIKE 'E11%' OR dd.icd_code LIKE 'E13%' OR dd.icd_code LIKE 'O24%'
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          dd.icd_code LIKE 'I50.2%' OR dd.icd_code LIKE 'I50.3%' OR dd.icd_code LIKE 'I50.4%'
        )
    )
),

glp1_admins AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.emar_id,
    e.charttime,
    e.medication
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
  JOIN
    cohort c
  ON
    e.hadm_id = c.hadm_id
  WHERE
    REGEXP_CONTAINS(UPPER(e.medication), r'(LIRAGLUTIDE|SEMAGLUTIDE|DULAGLUTIDE|EXENATIDE)')
    AND e.event_txt = 'Administered'
),

first_72h_admins AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    g.emar_id,
    g.charttime
  FROM
    glp1_admins g
  JOIN
    cohort c
  ON
    g.hadm_id = c.hadm_id
  WHERE
    g.charttime <= c.intime + INTERVAL 72 HOUR
),

last_24h_admins AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    g.emar_id,
    g.charttime
  FROM
    glp1_admins g
  JOIN
    cohort c
  ON
    g.hadm_id = c.hadm_id
  WHERE
    g.charttime >= c.outtime - INTERVAL 24 HOUR
),

first_72h_initiators AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    MIN(f.charttime) AS first_admin_time
  FROM
    first_72h_admins f
  GROUP BY
    f.subject_id, f.hadm_id
),

last_24h_initiators AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    MIN(l.charttime) AS last_admin_time
  FROM
    last_24h_admins l
  GROUP BY
    l.subject_id, l.hadm_id
),

cohort_counts AS (
  SELECT
    COUNT(DISTINCT c.hadm_id) AS total_patients,
    COUNT(DISTINCT CASE WHEN g.hadm_id IS NOT NULL THEN g.hadm_id END) AS glp1_ever,
    COUNT(DISTINCT f.hadm_id) AS initiated_first_72h,
    COUNT(DISTINCT l.hadm_id) AS initiated_last_24h
  FROM
    cohort c
  LEFT JOIN
    glp1_admins g
  ON
    c.hadm_id = g.hadm_id
  LEFT JOIN
    first_72h_initiators f
  ON
    c.hadm_id = f.hadm_id
  LEFT JOIN
    last_24h_initiators l
  ON
    c.hadm_id = l.hadm_id
)

SELECT
  total_patients,
  glp1_ever,
  initiated_first_72h,
  initiated_last_24h,
  ROUND(SAFE_DIVIDE(glp1_ever, total_patients) * 100, 2) AS prevalence_pct,
  ROUND(SAFE_DIVIDE(initiated_first_72h, total_patients) * 100, 2) AS initiation_first_72h_pct,
  ROUND(SAFE_DIVIDE(initiated_last_24h, total_patients) * 100, 2) AS initiation_last_24h_pct,
  ROUND(SAFE_DIVIDE(initiated_last_24h - initiated_first_72h, total_patients) * 100, 2) AS abs_change_initiation_pct,
  ROUND(SAFE_DIVIDE(initiated_last_24h - initiated_first_72h, NULLIF(initiated_first_72h, 0)) * 100, 2) AS rel_change_initiation_pct
FROM
  cohort_counts;