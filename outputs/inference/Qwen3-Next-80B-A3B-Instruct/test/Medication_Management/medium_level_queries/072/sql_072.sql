WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON a.hadm_id = d1.hadm_id
    AND d1.icd_version = 10
    AND d1.icd_code LIKE 'E11%'
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON a.hadm_id = d2.hadm_id
    AND d2.icd_version = 10
    AND d2.icd_code LIKE 'I50%'
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

glp1_drugs AS (
  SELECT DISTINCT
    p.hadm_id,
    p.starttime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE LOWER(p.drug) LIKE LOWER('%liraglutide%')
     OR LOWER(p.drug) LIKE LOWER('%semaglutide%')
     OR LOWER(p.drug) LIKE LOWER('%dulaglutide%')
     OR LOWER(p.drug) LIKE LOWER('%exenatide%')
     OR LOWER(p.drug) LIKE LOWER('%lixisenatide%')
     OR LOWER(p.drug) LIKE LOWER('%albiglutide%')
     OR LOWER(p.drug) LIKE LOWER('%Victoza%')
     OR LOWER(p.drug) LIKE LOWER('%Ozempic%')
     OR LOWER(p.drug) LIKE LOWER('%Trulicity%')
     OR LOWER(p.drug) LIKE LOWER('%Byetta%')
     OR LOWER(p.drug) LIKE LOWER('%Bydureon%')
     OR LOWER(p.drug) LIKE LOWER('%Adlyxin%')
     OR LOWER(p.drug) LIKE LOWER('%Saxenda%')
     OR LOWER(p.drug) LIKE LOWER('%Wegovy%')
     OR LOWER(p.drug) LIKE LOWER('%GLP-1%')
     OR LOWER(p.drug) LIKE LOWER('%glucagon-like peptide%')
  -- Exclude non-GLP-1 drugs that might match by accident
  AND LOWER(p.drug) NOT LIKE LOWER('%insulin%')
  AND LOWER(p.drug) NOT LIKE LOWER('%metformin%')
  AND LOWER(p.drug) NOT LIKE LOWER('%sulfonylurea%')
  AND LOWER(p.drug) NOT LIKE LOWER('%DPP-4%')
),

first_12h AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS n_initiated
  FROM cohort c
  INNER JOIN glp1_drugs g
    ON c.hadm_id = g.hadm_id
    AND g.starttime >= c.admittime
    AND g.starttime <= c.admittime + INTERVAL 12 HOUR
),

last_24h AS (
  SELECT COUNT(DISTINCT c.hadm_id) AS n_initiated
  FROM cohort c
  INNER JOIN glp1_drugs g
    ON c.hadm_id = g.hadm_id
    AND g.starttime >= c.dischtime - INTERVAL 24 HOUR
    AND g.starttime <= c.dischtime
),

total_cohort AS (
  SELECT COUNT(*) AS n_total
  FROM cohort
)

SELECT
  ROUND(100.0 * f.n_initiated / t.n_total, 2) AS percent_first_12h,
  ROUND(100.0 * l.n_initiated / t.n_total, 2) AS percent_last_24h,
  ROUND(100.0 * f.n_initiated / t.n_total, 2) - ROUND(100.0 * l.n_initiated / t.n_total, 2) AS net_percentage_point_change
FROM first_12h f
CROSS JOIN last_24h l
CROSS JOIN total_cohort t;