WITH cohort_admissions AS (
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
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- admission length at least 72 hours
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    -- must have T2DM diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- ICD-10 Type 2 diabetes (E11.*) OR ICD-9 diabetes (250.*)
          (d.icd_version = 10 AND LOWER(d.icd_code) LIKE 'e11%')
          OR (d.icd_version = 9 AND LOWER(d.icd_code) LIKE '250%')
          OR LOWER(COALESCE(dd.long_title, '')) LIKE '%type 2 diab%'
        )
      LIMIT 1
    )
    -- must have Heart Failure diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- ICD-10 heart failure (I50.*) OR ICD-9 heart failure (428.*)
          (d.icd_version = 10 AND LOWER(d.icd_code) LIKE 'i50%')
          OR (d.icd_version = 9 AND LOWER(d.icd_code) LIKE '428%')
          OR LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%'
        )
      LIMIT 1
    )
),

glp_med_starts AS (
  -- union prescriptions and pharmacy tables to capture GLP-1 starts
  SELECT
    hadm_id,
    starttime,
    drug AS drug_name
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    starttime IS NOT NULL
    AND hadm_id IS NOT NULL
    AND (
      LOWER(drug) LIKE '%liraglutide%'
      OR LOWER(drug) LIKE '%semaglutide%'
      OR LOWER(drug) LIKE '%exenatide%'
      OR LOWER(drug) LIKE '%dulaglutide%'
      OR LOWER(drug) LIKE '%lixisenatide%'
      OR LOWER(drug) LIKE '%albiglutide%'
      OR LOWER(drug) LIKE '%efpeglenatide%'
      -- common brands
      OR LOWER(drug) LIKE '%victoza%'
      OR LOWER(drug) LIKE '%ozempic%'
      OR LOWER(drug) LIKE '%byetta%'
      OR LOWER(drug) LIKE '%bydureon%'
      OR LOWER(drug) LIKE '%trulicity%'
      OR LOWER(drug) LIKE '%adlyxin%'
      OR LOWER(drug) LIKE '%rybelsus%'
    )

  UNION ALL

  SELECT
    hadm_id,
    starttime,
    medication AS drug_name
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy`
  WHERE
    starttime IS NOT NULL
    AND hadm_id IS NOT NULL
    AND (
      LOWER(medication) LIKE '%liraglutide%'
      OR LOWER(medication) LIKE '%semaglutide%'
      OR LOWER(medication) LIKE '%exenatide%'
      OR LOWER(medication) LIKE '%dulaglutide%'
      OR LOWER(medication) LIKE '%lixisenatide%'
      OR LOWER(medication) LIKE '%albiglutide%'
      OR LOWER(medication) LIKE '%efpeglenatide%'
      OR LOWER(medication) LIKE '%victoza%'
      OR LOWER(medication) LIKE '%ozempic%'
      OR LOWER(medication) LIKE '%byetta%'
      OR LOWER(medication) LIKE '%bydureon%'
      OR LOWER(medication) LIKE '%trulicity%'
      OR LOWER(medication) LIKE '%adlyxin%'
      OR LOWER(medication) LIKE '%rybelsus%'
    )
),

first_glp_start AS (
  -- for each admission, find earliest GLP-1 starttime (if any)
  SELECT
    hadm_id,
    MIN(starttime) AS first_starttime
  FROM
    glp_med_starts
  GROUP BY
    hadm_id
)

SELECT
  COUNT(DISTINCT c.hadm_id) AS cohort_size,
  SUM(CASE WHEN f.first_starttime IS NOT NULL
            AND f.first_starttime >= c.admittime
            AND f.first_starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
           THEN 1 ELSE 0 END) AS n_started_first72h,
  SUM(CASE WHEN f.first_starttime IS NOT NULL
            AND f.first_starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
            AND f.first_starttime < c.dischtime
           THEN 1 ELSE 0 END) AS n_started_final12h,
  ROUND(
    100.0 * SAFE_DIVIDE(
      SUM(CASE WHEN f.first_starttime IS NOT NULL
                AND f.first_starttime >= c.admittime
                AND f.first_starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
               THEN 1 ELSE 0 END),
      COUNT(DISTINCT c.hadm_id)
    ), 2
  ) AS pct_started_first72h,
  ROUND(
    100.0 * SAFE_DIVIDE(
      SUM(CASE WHEN f.first_starttime IS NOT NULL
                AND f.first_starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
                AND f.first_starttime < c.dischtime
               THEN 1 ELSE 0 END),
      COUNT(DISTINCT c.hadm_id)
    ), 2
  ) AS pct_started_final12h,
  ROUND(
    100.0 * SAFE_DIVIDE(
      SUM(CASE WHEN f.first_starttime IS NOT NULL
                AND f.first_starttime >= c.admittime
                AND f.first_starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
               THEN 1 ELSE 0 END)
      -
      SUM(CASE WHEN f.first_starttime IS NOT NULL
                AND f.first_starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
                AND f.first_starttime < c.dischtime
               THEN 1 ELSE 0 END),
      COUNT(DISTINCT c.hadm_id)
    ), 2
  ) AS absolute_difference_percentage_points
FROM
  cohort_admissions c
  LEFT JOIN first_glp_start f
    ON c.hadm_id = f.hadm_id;