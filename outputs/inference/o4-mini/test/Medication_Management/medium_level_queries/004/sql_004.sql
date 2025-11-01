WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- age 45–55, male
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    -- only true inpatient admissions
    AND a.hospital_expire_flag IN (0,1)
),
dx AS (
  SELECT
    subject_id,
    hadm_id,
    ARRAY_AGG(DISTINCT
      CASE
        WHEN icd_version = 9 AND icd_code LIKE '250%' THEN 'T2DM'
        WHEN icd_version = 9 AND icd_code LIKE '428%' THEN 'HF'
        ELSE NULL
      END
    ) AS dx_list
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY
    subject_id,
    hadm_id
),
cohort_dx AS (
  SELECT
    c.*
  FROM
    cohort c
    JOIN dx
      ON c.subject_id = dx.subject_id
      AND c.hadm_id    = dx.hadm_id
  WHERE
    -- require both T2DM and HF in dx_list
    ARRAY_LENGTH(
      ARRAY(
        SELECT x FROM UNNEST(dx.dx_list) AS x
        WHERE x IN ('T2DM','HF')
      )
    ) = 2
),
glp_drugs AS (
  -- common GLP-1 agonists
  SELECT 'exenatide'    AS drug_name UNION ALL
  SELECT 'liraglutide'  UNION ALL
  SELECT 'dulaglutide'  UNION ALL
  SELECT 'semaglutide'  UNION ALL
  SELECT 'lixisenatide'
),
presc AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN glp_drugs g
      ON LOWER(p.drug) LIKE CONCAT('%', g.drug_name, '%')
),
first72 AS (
  SELECT DISTINCT
    c.hadm_id
  FROM
    cohort_dx c
    JOIN presc pr
      ON c.subject_id = pr.subject_id
      AND c.hadm_id    = pr.hadm_id
  WHERE
    pr.starttime BETWEEN c.admittime
                     AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
),
last48 AS (
  SELECT DISTINCT
    c.hadm_id
  FROM
    cohort_dx c
    JOIN presc pr
      ON c.subject_id = pr.subject_id
      AND c.hadm_id    = pr.hadm_id
  WHERE
    pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
                     AND c.dischtime
),
counts AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS total_hadms,
    COUNT(DISTINCT CASE WHEN hadm_id IN (SELECT hadm_id FROM first72) THEN hadm_id END) AS n_first72,
    COUNT(DISTINCT CASE WHEN hadm_id IN (SELECT hadm_id FROM last48) THEN hadm_id END)  AS n_last48
  FROM
    cohort_dx
)
SELECT
  total_hadms,
  n_first72,
  SAFE_DIVIDE(n_first72, total_hadms) * 100 AS pct_started_within_72h,
  n_last48,
  SAFE_DIVIDE(n_last48, total_hadms) * 100 AS pct_in_last_48h,
  (SAFE_DIVIDE(n_last48, total_hadms) - SAFE_DIVIDE(n_first72, total_hadms)) * 100 AS net_change_pct_points
FROM
  counts;