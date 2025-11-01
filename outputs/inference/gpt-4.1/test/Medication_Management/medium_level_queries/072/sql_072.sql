WITH cohort AS (
  -- Male inpatients aged 79-89 with T2DM and HF
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  -- Age filter
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    -- Must have both T2DM and HF diagnoses
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- T2DM ICD-10 E11.*, ICD-9 250.00-250.92 (excluding 250.1x for type 1)
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '250.%' AND SUBSTR(d.icd_code,5,1) != '1')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- HF ICD-10 I50.*, ICD-9 428.*
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
        )
    )
),
glp1_presc AS (
  -- Identify GLP-1 RA prescriptions in relevant windows
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.drug
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions pr
  WHERE LOWER(pr.drug) LIKE '%exenatide%'
     OR LOWER(pr.drug) LIKE '%liraglutide%'
     OR LOWER(pr.drug) LIKE '%dulaglutide%'
     OR LOWER(pr.drug) LIKE '%semaglutide%'
     OR LOWER(pr.drug) LIKE '%lixisenatide%'
     OR LOWER(pr.drug) LIKE '%albiglutide%'
),
first12h AS (
  -- First GLP-1 RA initiation in first 12h after admission
  SELECT
    c.subject_id,
    c.hadm_id,
    MIN(g.starttime) AS first_presc_time
  FROM cohort c
  JOIN glp1_presc g
    ON c.subject_id = g.subject_id AND c.hadm_id = g.hadm_id
    AND g.starttime >= c.admittime
    AND g.starttime < DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
final24h AS (
  -- First GLP-1 RA initiation in final 24h before discharge
  SELECT
    c.subject_id,
    c.hadm_id,
    MIN(g.starttime) AS first_presc_time
  FROM cohort c
  JOIN glp1_presc g
    ON c.subject_id = g.subject_id AND c.hadm_id = g.hadm_id
    AND g.starttime >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR)
    AND g.starttime < c.dischtime
  GROUP BY c.subject_id, c.hadm_id
)
SELECT
  COUNT(DISTINCT c.hadm_id) AS n_total,
  COUNT(DISTINCT f12.hadm_id) AS n_first12h,
  ROUND(COUNT(DISTINCT f12.hadm_id) * 100.0 / COUNT(DISTINCT c.hadm_id), 2) AS pct_first12h,
  COUNT(DISTINCT f24.hadm_id) AS n_final24h,
  ROUND(COUNT(DISTINCT f24.hadm_id) * 100.0 / COUNT(DISTINCT c.hadm_id), 2) AS pct_final24h,
  ROUND(
    (COUNT(DISTINCT f24.hadm_id) * 100.0 / COUNT(DISTINCT c.hadm_id))
    - (COUNT(DISTINCT f12.hadm_id) * 100.0 / COUNT(DISTINCT c.hadm_id)),
    2
  ) AS net_pct_point_change
FROM cohort c
LEFT JOIN first12h f12 ON c.hadm_id = f12.hadm_id
LEFT JOIN final24h f24 ON c.hadm_id = f24.hadm_id
;