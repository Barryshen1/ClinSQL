WITH cohort AS (
  -- male inpatients age 57-67 (by anchor_age), with both diabetes and acute heart failure diagnoses in the same admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.hadm_id IS NOT NULL
    -- require at least one diabetes diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    -- require at least one (acute) heart failure diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
        AND (LOWER(dd.long_title) LIKE '%acute%' OR LOWER(dd.long_title) LIKE '%decomp%' OR LOWER(dd.long_title) LIKE '%acute on chronic%')
    )
),
meds_union AS (
  -- union candidate medication orders / prescriptions with start times
  SELECT
    hadm_id,
    LOWER(COALESCE(drug, '')) AS drug_text,
    starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE starttime IS NOT NULL

  UNION ALL

  SELECT
    hadm_id,
    LOWER(COALESCE(medication, '')) AS drug_text,
    starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE starttime IS NOT NULL
),
glp_orders AS (
  -- identify GLP-1 orders within the admission window and link to cohort
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    m.starttime
  FROM
    cohort c
  JOIN
    meds_union m
    ON m.hadm_id = c.hadm_id
  WHERE
    -- basic medication name matching for common GLP-1 receptor agonists / brands
    REGEXP_CONTAINS(m.drug_text, r'exenatide|liraglutide|dulaglutide|semaglutide|lixisenatide|albiglutide|tirzepatide|byetta|victoza|trulicity|ozempic|rybelsus|adlyxin|tanzeum')
    -- ensure the order/start is within the admission bounds and not before admission
    AND m.starttime >= c.admittime
    AND m.starttime <= c.dischtime
),
earliest_glp_per_adm AS (
  -- earliest GLP-1 starttime per admission
  SELECT
    hadm_id,
    MIN(starttime) AS first_glp_start,
    MIN(admittime) AS admittime,
    MIN(dischtime) AS dischtime
  FROM
    glp_orders
  GROUP BY hadm_id
)

SELECT
  COUNT(DISTINCT c.hadm_id) AS cohort_size,
  COUNT(DISTINCT eg.hadm_id) AS n_glp_any,
  ROUND(100.0 * SAFE_DIVIDE(COUNT(DISTINCT eg.hadm_id), COUNT(DISTINCT c.hadm_id)), 2) AS prevalence_pct,
  -- first 72h initiations: earliest GLP start <= admittime + 72 hours
  SUM(CASE WHEN eg.first_glp_start IS NOT NULL AND eg.first_glp_start <= TIMESTAMP_ADD(eg.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS n_first72,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN eg.first_glp_start IS NOT NULL AND eg.first_glp_start <= TIMESTAMP_ADD(eg.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END), COUNT(DISTINCT c.hadm_id)), 2) AS pct_first72,
  -- final 24h initiations: earliest GLP start >= dischtime - 24 hours
  SUM(CASE WHEN eg.first_glp_start IS NOT NULL AND eg.first_glp_start >= TIMESTAMP_SUB(eg.dischtime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS n_final24,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN eg.first_glp_start IS NOT NULL AND eg.first_glp_start >= TIMESTAMP_SUB(eg.dischtime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END), COUNT(DISTINCT c.hadm_id)), 2) AS pct_final24,
  -- absolute and relative change (relative change as percent change vs first72)
  ROUND(
    ( ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN eg.first_glp_start IS NOT NULL AND eg.first_glp_start >= TIMESTAMP_SUB(eg.dischtime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END), COUNT(DISTINCT c.hadm_id)), 6)
      - ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN eg.first_glp_start IS NOT NULL AND eg.first_glp_start <= TIMESTAMP_ADD(eg.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END), COUNT(DISTINCT c.hadm_id)), 6)
    ), 2) AS absolute_change_pct_points,
  CASE
    WHEN ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN eg.first_glp_start IS NOT NULL AND eg.first_glp_start <= TIMESTAMP_ADD(eg.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END), COUNT(DISTINCT c.hadm_id)), 6) = 0
      THEN NULL
    ELSE ROUND(
      100.0 * (
        SAFE_DIVIDE(
          ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN eg.first_glp_start IS NOT NULL AND eg.first_glp_start >= TIMESTAMP_SUB(eg.dischtime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END), COUNT(DISTINCT c.hadm_id)), 6),
          ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN eg.first_glp_start IS NOT NULL AND eg.first_glp_start <= TIMESTAMP_ADD(eg.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END), COUNT(DISTINCT c.hadm_id)), 6)
        ) - 1
      ), 2)
  END AS relative_change_percent
FROM
  cohort c
LEFT JOIN
  earliest_glp_per_adm eg
  ON c.hadm_id = eg.hadm_id;