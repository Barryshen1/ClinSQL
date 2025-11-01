WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 36
    -- Diabetes diagnosis E10–E14
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND REGEXP_CONTAINS(d.icd_code, r'^E1[0-4]')
    )
    -- Acute heart failure, ICD-10 I50.2x
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        USING(icd_code, icd_version)
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND (
          REGEXP_CONTAINS(d.icd_code, r'^I50\.2')
          OR LOWER(dd.long_title) LIKE '%acute heart failure%'
        )
    )
),
glp1_rx AS (
  SELECT
    p.hadm_id,
    p.starttime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON p.hadm_id = c.hadm_id
  WHERE
    -- Common injectable GLP-1 drugs
    REGEXP_CONTAINS(LOWER(p.drug), r'(exenatide|liraglutide|dulaglutide|semaglutide)')
    -- Restrict to injectable routes
    AND (
      LOWER(p.route) LIKE '%sc%'
      OR LOWER(p.route) LIKE '%subcutaneous%'
    )
    AND p.starttime IS NOT NULL
),
flags AS (
  SELECT
    c.hadm_id,
    MAX(IF(TIMESTAMP_DIFF(r.starttime, c.admittime, HOUR) BETWEEN 0 AND 24, 1, 0)) AS started_first_24h,
    MAX(IF(r.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime, 1, 0)) AS started_last_12h
  FROM
    cohort c
    LEFT JOIN glp1_rx r
      ON r.hadm_id = c.hadm_id
  GROUP BY
    c.hadm_id
),
agg AS (
  SELECT
    COUNT(*) AS total_admissions,
    SUM(started_first_24h) AS count_first_24h,
    SUM(started_last_12h) AS count_last_12h
  FROM
    flags
)
SELECT
  ROUND(100.0 * count_first_24h / total_admissions, 2) AS pct_started_first_24h,
  ROUND(100.0 * count_last_12h / total_admissions, 2) AS pct_started_last_12h
FROM
  agg;