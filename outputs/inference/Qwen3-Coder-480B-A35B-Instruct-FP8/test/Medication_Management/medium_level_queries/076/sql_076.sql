WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 36
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE
        REGEXP_CONTAINS(dd.icd_code, r'^E1[0-4]') -- Diabetes
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE
        REGEXP_CONTAINS(dd.icd_code, r'^I50') -- Acute heart failure
    )
),

glp1_meds AS (
  SELECT
    pr.hadm_id,
    pr.starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE
    LOWER(pr.drug) LIKE '%semaglutide%'
    OR LOWER(pr.drug) LIKE '%dulaglutide%'
    OR LOWER(pr.drug) LIKE '%exenatide%'
    OR LOWER(pr.drug) LIKE '%liraglutide%'
    AND pr.route IN ('injection', 'subcutaneous')
),

timing_flags AS (
  SELECT
    c.hadm_id,
    MAX(CASE WHEN g.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS started_first_24h,
    MAX(CASE WHEN g.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 1 ELSE 0 END) AS started_last_12h
  FROM
    cohort c
  LEFT JOIN
    glp1_meds g
  ON
    c.hadm_id = g.hadm_id
  GROUP BY
    c.hadm_id
)

SELECT
  ROUND(100 * AVG(started_first_24h), 2) AS percent_started_first_24h,
  ROUND(100 * AVG(started_last_12h), 2) AS percent_started_last_12h
FROM
  timing_flags;