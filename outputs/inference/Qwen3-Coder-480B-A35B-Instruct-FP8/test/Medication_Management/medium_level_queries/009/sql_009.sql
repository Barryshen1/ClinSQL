WITH cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  USING
    (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  USING
    (hadm_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      USING (icd_code, icd_version)
      WHERE
        (dd.icd_code LIKE 'E10%' OR dd.icd_code LIKE 'E11%' OR dd.icd_code LIKE '250%')
        OR (dd.icd_code LIKE 'I50%' OR dd.icd_code LIKE '428%')
      GROUP BY hadm_id
      HAVING
        COUNT(DISTINCT CASE WHEN dd.icd_code LIKE 'E10%' OR dd.icd_code LIKE 'E11%' OR dd.icd_code LIKE '250%' THEN 1 END) > 0
        AND COUNT(DISTINCT CASE WHEN dd.icd_code LIKE 'I50%' OR dd.icd_code LIKE '428%' THEN 1 END) > 0
    )
),

meds_first_24h AS (
  SELECT
    c.hadm_id,
    c.stay_id,
    e.medication,
    MIN(e.charttime) AS first_admin_time
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
  USING
    (hadm_id)
  WHERE
    e.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 1 DAY)
    AND LOWER(e.medication) LIKE '%insulin%'
  GROUP BY
    c.hadm_id, c.stay_id, e.medication
),

meds_last_24h AS (
  SELECT
    c.hadm_id,
    c.stay_id,
    e.medication,
    MIN(e.charttime) AS first_admin_time
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` e
  USING
    (hadm_id)
  WHERE
    e.charttime BETWEEN DATETIME_SUB(c.outtime, INTERVAL 1 DAY) AND c.outtime
    AND LOWER(e.medication) LIKE '%insulin%'
  GROUP BY
    c.hadm_id, c.stay_id, e.medication
),

first_window_summary AS (
  SELECT
    hadm_id,
    COUNT(*) AS total_first_window,
    COUNTIF(LOWER(medication) LIKE '%insulin%') AS insulin_first,
    COUNTIF(LOWER(medication) LIKE '%metformin%' OR LOWER(medication) LIKE '%glyburide%' OR LOWER(medication) LIKE '%glipizide%') AS oral_first
  FROM meds_first_24h
  GROUP BY hadm_id
),

last_window_summary AS (
  SELECT
    hadm_id,
    COUNT(*) AS total_last_window,
    COUNTIF(LOWER(medication) LIKE '%insulin%') AS insulin_last,
    COUNTIF(LOWER(medication) LIKE '%metformin%' OR LOWER(medication) LIKE '%glyburide%' OR LOWER(medication) LIKE '%glipizide%') AS oral_last
  FROM meds_last_24h
  GROUP BY hadm_id
),

combined AS (
  SELECT
    COALESCE(f.hadm_id, l.hadm_id) AS hadm_id,
    IFNULL(f.total_first_window, 0) AS total_first_window,
    IFNULL(f.insulin_first, 0) AS insulin_first,
    IFNULL(f.oral_first, 0) AS oral_first,
    IFNULL(l.total_last_window, 0) AS total_last_window,
    IFNULL(l.insulin_last, 0) AS insulin_last,
    IFNULL(l.oral_last, 0) AS oral_last
  FROM
    first_window_summary f
  FULL OUTER JOIN
    last_window_summary l
  USING (hadm_id)
)

SELECT
  ROUND(100 * AVG(SAFE_DIVIDE(insulin_first, total_first_window)), 2) AS insulin_first_24h_pct,
  ROUND(100 * AVG(SAFE_DIVIDE(oral_first, total_first_window)), 2) AS oral_first_24h_pct,
  ROUND(100 * AVG(SAFE_DIVIDE(insulin_last, total_last_window)), 2) AS insulin_last_24h_pct,
  ROUND(100 * AVG(SAFE_DIVIDE(oral_last, total_last_window)), 2) AS oral_last_24h_pct,
  ROUND(100 * (
    AVG(SAFE_DIVIDE(insulin_first, total_first_window)) - AVG(SAFE_DIVIDE(insulin_last, total_last_window))
  ), 2) AS insulin_pct_diff,
  ROUND(100 * (
    AVG(SAFE_DIVIDE(oral_first, total_first_window)) - AVG(SAFE_DIVIDE(oral_last, total_last_window))
  ), 2) AS oral_pct_diff
FROM
  combined;