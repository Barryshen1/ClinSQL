WITH base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admit_year,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS real_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 71 AND 81
),
dx_flags AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    MAX(CASE WHEN d.icd_version = 9 AND (d.icd_code LIKE '250%' OR d.icd_code LIKE '249%')
              OR d.icd_version = 10 AND (d.icd_code LIKE 'E08%' OR d.icd_code LIKE 'E09%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR d.icd_code LIKE 'E13%')
             THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN d.icd_version = 9 AND (d.icd_code LIKE '4280%' OR d.icd_code LIKE '4281%' OR d.icd_code LIKE '4282%' OR d.icd_code LIKE '4283%' OR d.icd_code LIKE '4284%')
              OR d.icd_version = 10 AND (d.icd_code LIKE 'I5021%' OR d.icd_code LIKE 'I5023%' OR d.icd_code LIKE 'I5031%' OR d.icd_code LIKE 'I5033%' OR d.icd_code LIKE 'I5041%' OR d.icd_code LIKE 'I5043%' OR d.icd_code LIKE 'I509%')
             THEN 1 ELSE 0 END) AS has_ahf
  FROM
    base b
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON b.subject_id = d.subject_id AND b.hadm_id = d.hadm_id
  GROUP BY b.subject_id, b.hadm_id
),
cohort AS (
  SELECT
    b.*
  FROM
    base b
  JOIN
    dx_flags f
    ON b.subject_id = f.subject_id AND b.hadm_id = f.hadm_id
  WHERE
    f.has_diabetes = 1 AND f.has_ahf = 1
),
drug_inits AS (
  SELECT
    c.hadm_id,
    MIN(CASE WHEN LOWER(pr.drug) LIKE '%metformin%' THEN pr.starttime END) AS metformin_start,
    MIN(CASE WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN pr.starttime END) AS sulfonylurea_start,
    MIN(CASE WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN pr.starttime END) AS dpp4_start,
    MIN(CASE WHEN LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN pr.starttime END) AS sglt2_start,
    MIN(CASE WHEN LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN pr.starttime END) AS tzd_start
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  GROUP BY c.hadm_id
),
flags AS (
  SELECT
    c.hadm_id,
    -- Denorm
    c.admittime,
    c.dischtime,
    CASE WHEN metformin_start IS NOT NULL AND metformin_start BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END AS metformin_first72h,
    CASE WHEN metformin_start IS NOT NULL AND metformin_start BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END AS metformin_last48h,
    CASE WHEN sulfonylurea_start IS NOT NULL AND sulfonylurea_start BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END AS sulfonylurea_first72h,
    CASE WHEN sulfonylurea_start IS NOT NULL AND sulfonylurea_start BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END AS sulfonylurea_last48h,
    CASE WHEN dpp4_start IS NOT NULL AND dpp4_start BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END AS dpp4_first72h,
    CASE WHEN dpp4_start IS NOT NULL AND dpp4_start BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END AS dpp4_last48h,
    CASE WHEN sglt2_start IS NOT NULL AND sglt2_start BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END AS sglt2_first72h,
    CASE WHEN sglt2_start IS NOT NULL AND sglt2_start BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END AS sglt2_last48h,
    CASE WHEN tzd_start IS NOT NULL AND tzd_start BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END AS tzd_first72h,
    CASE WHEN tzd_start IS NOT NULL AND tzd_start BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1 ELSE 0 END AS tzd_last48h
  FROM
    cohort c
  LEFT JOIN
    drug_inits di
    ON c.hadm_id = di.hadm_id
),
rates AS (
  SELECT
    COUNT(*) AS denom,
    SUM(metformin_first72h) AS metformin_first72h_num,
    SUM(metformin_last48h) AS metformin_last48h_num,
    SUM(sulfonylurea_first72h) AS sulfonylurea_first72h_num,
    SUM(sulfonylurea_last48h) AS sulfonylurea_last48h_num,
    SUM(dpp4_first72h) AS dpp4_first72h_num,
    SUM(dpp4_last48h) AS dpp4_last48h_num,
    SUM(sglt2_first72h) AS sglt2_first72h_num,
    SUM(sglt2_last48h) AS sglt2_last48h_num,
    SUM(tzd_first72h) AS tzd_first72h_num,
    SUM(tzd_last48h) AS tzd_last48h_num
  FROM flags
)
SELECT
  'Metformin' AS drug_class,
  ROUND(100 * metformin_first72h_num / denom, 2) AS rate_first72h_percent,
  ROUND(100 * metformin_last48h_num / denom, 2) AS rate_last48h_percent
FROM rates
UNION ALL SELECT 'Sulfonylureas', ROUND(100 * sulfonylurea_first72h_num / denom, 2), ROUND(100 * sulfonylurea_last48h_num / denom, 2) FROM rates
UNION ALL SELECT 'DPP-4', ROUND(100 * dpp4_first72h_num / denom, 2), ROUND(100 * dpp4_last48h_num / denom, 2) FROM rates
UNION ALL SELECT 'SGLT2', ROUND(100 * sglt2_first72h_num / denom, 2), ROUND(100 * sglt2_last48h_num / denom, 2) FROM rates
UNION ALL SELECT 'Thiazolidinediones', ROUND(100 * tzd_first72h_num / denom, 2), ROUND(100 * tzd_last48h_num / denom, 2) FROM rates
;