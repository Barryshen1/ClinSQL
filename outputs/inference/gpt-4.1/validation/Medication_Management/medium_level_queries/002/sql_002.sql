WITH cohort AS (
  -- Female inpatients aged 59-69, LOS >=48h, with T2DM and HF
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- T2DM diagnosis
    JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (
          (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250[0-9][02]$')) -- 250.x0, 250.x2
          OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E11'))
        )
    ) t2dm ON a.hadm_id = t2dm.hadm_id
    -- Heart failure diagnosis
    JOIN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (
          (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428'))
          OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
        )
    ) hf ON a.hadm_id = hf.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 48
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

glp1_drugs AS (
  -- List of GLP-1 agonist drug names (lowercase for matching)
  SELECT 'exenatide' AS drug UNION ALL
  SELECT 'liraglutide' UNION ALL
  SELECT 'dulaglutide' UNION ALL
  SELECT 'semaglutide' UNION ALL
  SELECT 'lixisenatide' UNION ALL
  SELECT 'albiglutide'
),

glp1_emar AS (
  -- Actual administrations from EMAR
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime,
    LOWER(e.medication) AS medication,
    d.route
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` d
      ON e.subject_id = d.subject_id
      AND e.emar_id = d.emar_id
      AND e.emar_seq = d.emar_seq
  WHERE
    EXISTS (
      SELECT 1 FROM glp1_drugs
      WHERE LOWER(e.medication) LIKE CONCAT('%', drug, '%')
    )
    AND (
      LOWER(IFNULL(d.route, '')) LIKE '%sc%' -- subcutaneous
      OR LOWER(IFNULL(d.route, '')) LIKE '%subcut%'
      OR LOWER(IFNULL(d.route, '')) LIKE '%inject%'
      OR LOWER(IFNULL(d.route, '')) LIKE '%im%' -- intramuscular (rare)
    )
),

glp1_presc AS (
  -- Prescriptions fallback (if no EMAR record)
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    LOWER(pr.drug) AS drug,
    pr.route
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE
    EXISTS (
      SELECT 1 FROM glp1_drugs
      WHERE LOWER(pr.drug) LIKE CONCAT('%', drug, '%')
    )
    AND (
      LOWER(IFNULL(pr.route, '')) LIKE '%sc%'
      OR LOWER(IFNULL(pr.route, '')) LIKE '%subcut%'
      OR LOWER(IFNULL(pr.route, '')) LIKE '%inject%'
      OR LOWER(IFNULL(pr.route, '')) LIKE '%im%'
    )
),

glp1_admin AS (
  -- Combine EMAR and prescriptions (prefer EMAR if available)
  SELECT
    c.subject_id,
    c.hadm_id,
    MIN(e.charttime) AS first_admin_time,
    MAX(e.charttime) AS last_admin_time
  FROM
    cohort c
    JOIN glp1_emar e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
  GROUP BY c.subject_id, c.hadm_id

  UNION ALL

  SELECT
    c.subject_id,
    c.hadm_id,
    MIN(pr.starttime) AS first_admin_time,
    MAX(pr.stoptime) AS last_admin_time
  FROM
    cohort c
    LEFT JOIN glp1_emar e
      ON c.subject_id = e.subject_id AND c.hadm_id = e.hadm_id
    JOIN glp1_presc pr
      ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE e.subject_id IS NULL -- only if no EMAR record
  GROUP BY c.subject_id, c.hadm_id
),

-- For each admission, check if GLP-1 was administered in first 48h or last 12h
adm_window AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- Any GLP-1 admin in first 48h?
    MAX(
      CASE
        WHEN ga.first_admin_time IS NOT NULL
          AND ga.first_admin_time >= c.admittime
          AND ga.first_admin_time < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
        THEN 1 ELSE 0
      END
    ) AS glp1_first48h,
    -- Any GLP-1 admin in last 12h?
    MAX(
      CASE
        WHEN ga.last_admin_time IS NOT NULL
          AND ga.last_admin_time >= DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR)
          AND ga.last_admin_time <= c.dischtime
        THEN 1 ELSE 0
      END
    ) AS glp1_last12h
  FROM
    cohort c
    LEFT JOIN glp1_admin ga
      ON c.subject_id = ga.subject_id AND c.hadm_id = ga.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
)

SELECT
  COUNT(*) AS n_admissions,
  SUM(glp1_first48h) AS n_glp1_first48h,
  SUM(glp1_last12h) AS n_glp1_last12h,
  ROUND(SAFE_DIVIDE(SUM(glp1_first48h), COUNT(*)) * 100, 2) AS prevalence_first48h_pct,
  ROUND(SAFE_DIVIDE(SUM(glp1_last12h), COUNT(*)) * 100, 2) AS prevalence_last12h_pct,
  ROUND(
    SAFE_DIVIDE(SUM(glp1_first48h), COUNT(*)) * 100
    - SAFE_DIVIDE(SUM(glp1_last12h), COUNT(*)) * 100,
    2
  ) AS absolute_pp_difference
FROM adm_window
;