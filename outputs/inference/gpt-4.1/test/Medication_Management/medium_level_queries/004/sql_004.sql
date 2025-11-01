WITH cohort AS (
  -- Male inpatients aged 45-55 with T2DM and heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- T2DM diagnosis
    JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE (
        -- ICD-10 E11.* (T2DM)
        (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'E11')
        -- ICD-9 250.x0, 250.x2 (T2DM)
        OR (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '250'
            AND RIGHT(d.icd_code, 2) IN ('00','02','10','12','20','22','30','32','40','42','50','52','60','62','70','72','80','82','90','92'))
      )
    ) t2dm ON a.hadm_id = t2dm.hadm_id
    -- Heart failure diagnosis
    JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE (
        -- ICD-10 I50.*
        (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'I50')
        -- ICD-9 428.*
        OR (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '428')
      )
    ) hf ON a.hadm_id = hf.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
),

glp1_prescriptions AS (
  -- GLP-1 prescriptions for cohort admissions
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN cohort c ON pr.subject_id = c.subject_id AND pr.hadm_id = c.hadm_id
  WHERE
    LOWER(pr.drug) LIKE '%liraglutide%'
    OR LOWER(pr.drug) LIKE '%exenatide%'
    OR LOWER(pr.drug) LIKE '%dulaglutide%'
    OR LOWER(pr.drug) LIKE '%semaglutide%'
    OR LOWER(pr.drug) LIKE '%albiglutide%'
),

glp1_started_within_72h AS (
  -- Admissions where GLP-1 was started within 72h of admit
  SELECT
    c.subject_id,
    c.hadm_id,
    MIN(pr.starttime) AS first_glp1_start
  FROM
    cohort c
    JOIN glp1_prescriptions pr ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE
    pr.starttime >= c.admittime
    AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),

glp1_on_last_48h AS (
  -- Admissions where GLP-1 was on in last 48h before discharge
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id
  FROM
    cohort c
    JOIN glp1_prescriptions pr ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE
    -- Any overlap between prescription and last 48h of admission
    pr.starttime < c.dischtime
    AND pr.stoptime > DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR)
)

SELECT
  COUNT(*) AS cohort_size,
  ROUND(100.0 * COUNT(DISTINCT sw.subject_id || '-' || sw.hadm_id) / COUNT(*), 2) AS pct_started_within_72h,
  ROUND(100.0 * COUNT(DISTINCT ol.subject_id || '-' || ol.hadm_id) / COUNT(*), 2) AS pct_on_last_48h,
  ROUND(
    100.0 * COUNT(DISTINCT ol.subject_id || '-' || ol.hadm_id) / COUNT(*)
    - 100.0 * COUNT(DISTINCT sw.subject_id || '-' || sw.hadm_id) / COUNT(*)
  , 2) AS net_change_pct
FROM
  cohort c
  LEFT JOIN glp1_started_within_72h sw ON c.subject_id = sw.subject_id AND c.hadm_id = sw.hadm_id
  LEFT JOIN glp1_on_last_48h ol ON c.subject_id = ol.subject_id AND c.hadm_id = ol.hadm_id
;