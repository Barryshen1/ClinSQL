WITH
-- 1. Identify admissions with both T2DM and HF in ICD-10
dx AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN d.icd_version = 10 AND d.icd_code LIKE 'E11%' THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE WHEN d.icd_version = 10 AND d.icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_hf
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  GROUP BY
    hadm_id
  HAVING
    has_t2dm = 1
    AND has_hf = 1
),
-- 2. Filter admissions + patients for age 48-58
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN dx
      ON a.hadm_id = dx.hadm_id
  WHERE
    p.anchor_age BETWEEN 48 AND 58
),
-- 3. Find first GLP-1 injectable prescription per admission
glp1_inits AS (
  SELECT
    c.hadm_id,
    MIN(pr.starttime) AS init_time,
    MIN(c.admittime) AS admittime,
    MIN(c.dischtime) AS dischtime
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON c.hadm_id = pr.hadm_id
  WHERE
    -- common injectable GLP-1 agonists
    LOWER(pr.drug) LIKE '%exenatide%'
    OR LOWER(pr.drug) LIKE '%liraglutide%'
    OR LOWER(pr.drug) LIKE '%dulaglutide%'
    OR LOWER(pr.drug) LIKE '%semaglutide%'
    OR LOWER(pr.drug) LIKE '%lixisenatide%'
  GROUP BY
    c.hadm_id
),
-- 4. Combine cohort with initiation times (null init_time => never initiated)
demo AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    g.init_time
  FROM
    cohort c
    LEFT JOIN glp1_inits g
      ON c.hadm_id = g.hadm_id
)
-- 5. Final aggregation
SELECT
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN init_time IS NOT NULL
            AND init_time <= TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)
           THEN 1 ELSE 0 END) AS first_72h_count,
  SUM(CASE WHEN init_time IS NOT NULL
            AND init_time >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR)
           THEN 1 ELSE 0 END) AS last_48h_count,
  ROUND(100.0 * SUM(CASE WHEN init_time IS NOT NULL
                          AND init_time <= TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)
                         THEN 1 ELSE 0 END) / COUNT(*), 2) AS first_72h_pct,
  ROUND(100.0 * SUM(CASE WHEN init_time IS NOT NULL
                          AND init_time >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR)
                         THEN 1 ELSE 0 END) / COUNT(*), 2) AS last_48h_pct,
  ROUND(
    (100.0 * SUM(CASE WHEN init_time IS NOT NULL
                       AND init_time <= TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)
                      THEN 1 ELSE 0 END) / COUNT(*))
    -
    (100.0 * SUM(CASE WHEN init_time IS NOT NULL
                       AND init_time >= TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR)
                      THEN 1 ELSE 0 END) / COUNT(*))
  , 2) AS absolute_difference_pp
FROM
  demo;