WITH
-- 1) Identify admissions for males age 52-62
admissions_males AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),

-- 2) Diagnostic flags per admission: has_t2dm and has_hf
diagnoses_flag AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    MAX(
      CASE
        WHEN (
          d.icd_version = 10 AND LOWER(d.icd_code) LIKE 'e11%'
        ) THEN 1
        WHEN (
          d.icd_version = 9 AND LOWER(d.icd_code) LIKE '250%'
        ) THEN 1
        WHEN (
          LOWER(diag.long_title) LIKE '%diabetes%' AND (
            LOWER(diag.long_title) LIKE '%type 2%' OR
            LOWER(diag.long_title) LIKE '%type ii%' OR
            LOWER(diag.long_title) LIKE '%noninsulin%' OR
            LOWER(diag.long_title) LIKE '%non-insulin%'
          )
        ) THEN 1
        ELSE 0
      END
    ) AS has_t2dm,
    MAX(
      CASE
        WHEN (
          d.icd_version = 10 AND LOWER(d.icd_code) LIKE 'i50%'
        ) THEN 1
        WHEN (
          d.icd_version = 9 AND LOWER(d.icd_code) LIKE '428%'
        ) THEN 1
        WHEN (
          LOWER(diag.long_title) LIKE '%heart failure%'
        ) THEN 1
        ELSE 0
      END
    ) AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  GROUP BY
    d.subject_id, d.hadm_id
),

-- 3) Cohort: admissions that meet demographic + diagnosis criteria
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    admissions_males a
  JOIN
    diagnoses_flag df
    USING(subject_id, hadm_id)
  WHERE
    df.has_t2dm = 1
    AND df.has_hf = 1
),

-- 4) Medication orders/dispensations that look like injectable GLP-1s
glp1_orders AS (
  -- prescriptions
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime AS ord_time,
    LOWER(COALESCE(p.drug, '')) AS med_text,
    'prescriptions' AS source
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE
    p.starttime IS NOT NULL

  UNION ALL

  -- pharmacy table
  SELECT
    ph.subject_id,
    ph.hadm_id,
    ph.starttime AS ord_time,
    LOWER(COALESCE(ph.medication, '')) AS med_text,
    'pharmacy' AS source
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
  WHERE
    ph.starttime IS NOT NULL
),

-- 5) Filter GLP-1 related strings (injectable GLP-1 agents)
glp1_filtered AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    g.ord_time,
    g.med_text,
    g.source
  FROM
    glp1_orders g
  WHERE
    (
      g.med_text LIKE '%liraglutide%' OR
      g.med_text LIKE '%exenatide%' OR
      g.med_text LIKE '%dulaglutide%' OR
      g.med_text LIKE '%semaglutide%' OR
      g.med_text LIKE '%lixisenatide%' OR
      g.med_text LIKE '%albiglutide%' OR
      g.med_text LIKE '%efpeglenatide%' OR
      g.med_text LIKE '%glp-1%' OR
      g.med_text LIKE '%glp1%'
    )
),

-- 6) For each cohort admission, determine presence in first 24h and final 48h
-- Rewritten to use a LEFT JOIN + aggregation (de-correlates the previous EXISTS subqueries)
hadm_glp1_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MAX(
      CASE
        WHEN g.ord_time BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR) THEN 1
        ELSE 0
      END
    ) = 1 AS any_glp1_first24,
    MAX(
      CASE
        WHEN g.ord_time BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1
        ELSE 0
      END
    ) = 1 AS any_glp1_final48
  FROM
    cohort c
  LEFT JOIN
    glp1_filtered g
  ON
    g.hadm_id = c.hadm_id
  GROUP BY
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
)

-- Final aggregation: counts and percentages
SELECT
  COUNT(*) AS total_cohort,
  SUM(CASE WHEN any_glp1_first24 THEN 1 ELSE 0 END) AS n_first24,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN any_glp1_first24 THEN 1 ELSE 0 END), COUNT(*)), 2) AS pct_first24,
  SUM(CASE WHEN any_glp1_final48 THEN 1 ELSE 0 END) AS n_final48,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN any_glp1_final48 THEN 1 ELSE 0 END), COUNT(*)), 2) AS pct_final48,
  ROUND(
    100.0 * SAFE_DIVIDE(SUM(CASE WHEN any_glp1_final48 THEN 1 ELSE 0 END), COUNT(*))
    - 100.0 * SAFE_DIVIDE(SUM(CASE WHEN any_glp1_first24 THEN 1 ELSE 0 END), COUNT(*)),
    2
  ) AS absolute_change_percentage_points,
  CASE
    WHEN (100.0 * SAFE_DIVIDE(SUM(CASE WHEN any_glp1_first24 THEN 1 ELSE 0 END), COUNT(*))) = 0 THEN NULL
    ELSE ROUND(
      100.0 * SAFE_DIVIDE(
        (100.0 * SAFE_DIVIDE(SUM(CASE WHEN any_glp1_final48 THEN 1 ELSE 0 END), COUNT(*)))
        - (100.0 * SAFE_DIVIDE(SUM(CASE WHEN any_glp1_first24 THEN 1 ELSE 0 END), COUNT(*))),
        (100.0 * SAFE_DIVIDE(SUM(CASE WHEN any_glp1_first24 THEN 1 ELSE 0 END), COUNT(*)))
      ),
      2
    )
  END AS relative_change_percent
FROM
  hadm_glp1_flags;