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
    p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE d.long_title LIKE '%diabetes%'
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE d.long_title LIKE '%heart failure%'
    )
),

glp1_starts AS (
  SELECT
    c.hadm_id,
    CASE
      WHEN pr.starttime <= c.admittime + INTERVAL 24 HOUR THEN 1
      ELSE 0
    END AS started_in_first_24h,
    CASE
      WHEN pr.starttime >= c.dischtime - INTERVAL 12 HOUR THEN 1
      ELSE 0
    END AS started_in_last_12h
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON c.hadm_id = pr.hadm_id
  WHERE
    (LOWER(pr.drug) LIKE '%semaglutide%'
     OR LOWER(pr.drug) LIKE '%liraglutide%'
     OR LOWER(pr.drug) LIKE '%dulaglutide%'
     OR LOWER(pr.drug) LIKE '%exenatide%')
    AND LOWER(pr.route) LIKE '%subcut%'
    AND pr.starttime IS NOT NULL
)

SELECT
  ROUND(
    100.0 * SUM(started_in_first_24h) / COUNT(DISTINCT c.hadm_id),
    2
  ) AS pct_started_in_first_24h,
  ROUND(
    100.0 * SUM(started_in_last_12h) / COUNT(DISTINCT c.hadm_id),
    2
  ) AS pct_started_in_last_12h
FROM
  cohort c
LEFT JOIN
  glp1_starts g
  ON c.hadm_id = g.hadm_id;