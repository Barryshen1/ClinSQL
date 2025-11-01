WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 50 AND 60
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  HAVING
    SUM(CASE
      WHEN (
        (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%')
        OR (diag.icd_version = 9 AND diag.icd_code LIKE '250%')
      ) THEN 1
      ELSE 0
    END) > 0
    AND SUM(CASE
      WHEN (
        (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        OR (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
      ) THEN 1
      ELSE 0
    END) > 0
),
total_cohort AS (
  SELECT COUNT(*) AS total FROM cohort
),
init_12h AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS num_init
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime
    AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
    AND (
      LOWER(pr.drug) LIKE '%liraglutide%'
      OR LOWER(pr.drug) LIKE '%semaglutide%'
      OR LOWER(pr.drug) LIKE '%dulaglutide%'
      OR LOWER(pr.drug) LIKE '%exenatide%'
      OR LOWER(pr.drug) LIKE '%albiglutide%'
      OR LOWER(pr.drug) LIKE '%lixisenatide%'
    )
),
prev_72h AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS num_prev
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
  WHERE pr.starttime >= c.admittime
    AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR))
    AND (
      LOWER(pr.drug) LIKE '%liraglutide%'
      OR LOWER(pr.drug) LIKE '%semaglutide%'
      OR LOWER(pr.drug) LIKE '%dulaglutide%'
      OR LOWER(pr.drug) LIKE '%exenatide%'
      OR LOWER(pr.drug) LIKE '%albiglutide%'
      OR LOWER(pr.drug) LIKE '%lixisenatide%'
    )
)
SELECT
  i.num_init * 100.0 / t.total AS first_12h_initiation_pct,
  p.num_prev * 100.0 / t.total AS final_72h_prevalence_pct,
  (p.num_prev * 100.0 / t.total) - (i.num_init * 100.0 / t.total) AS net_pct_point_change
FROM total_cohort t
CROSS JOIN init_12h i
CROSS JOIN prev_72h p;