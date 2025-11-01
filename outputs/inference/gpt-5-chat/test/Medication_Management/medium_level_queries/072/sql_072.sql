WITH t2dm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'E11%')
     OR (icd_version = 9  AND (
           icd_code LIKE '250%0' OR icd_code LIKE '250%2'
         ))
),
hf AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'I50%')
     OR (icd_version = 9  AND icd_code LIKE '428%')
),
cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.hadm_id IN (SELECT hadm_id FROM t2dm)
    AND a.hadm_id IN (SELECT hadm_id FROM hf)
),
glp1_first12 AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE REGEXP_CONTAINS(
          LOWER(pr.drug),
          '(exenatide|liraglutide|semaglutide|dulaglutide|lixisenatide|albiglutide)'
        )
    AND pr.starttime >= c.admittime
    AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
),
glp1_last24 AS (
  SELECT DISTINCT c.hadm_id
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE REGEXP_CONTAINS(
          LOWER(pr.drug),
          '(exenatide|liraglutide|semaglutide|dulaglutide|lixisenatide|albiglutide)'
        )
    AND pr.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR)
    AND pr.starttime < c.dischtime
),
counts AS (
  SELECT
    COUNT(*) AS n_cohort,
    COUNT(DISTINCT f.hadm_id) AS n_first12,
    COUNT(DISTINCT l.hadm_id) AS n_last24
  FROM cohort c
  LEFT JOIN glp1_first12 f ON c.hadm_id = f.hadm_id
  LEFT JOIN glp1_last24  l ON c.hadm_id = l.hadm_id
)
SELECT
  n_cohort,
  n_first12,
  ROUND(100.0 * n_first12 / n_cohort, 2) AS pct_first12,
  n_last24,
  ROUND(100.0 * n_last24 / n_cohort, 2) AS pct_last24,
  ROUND(
    (100.0 * n_last24 / n_cohort) - 
    (100.0 * n_first12 / n_cohort),
    2
  ) AS net_pct_point_change
FROM counts;