WITH
-- 1. Identify T2DM and HF ICD codes
t2dm_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10 E11.*, ICD-9 250.x0, 250.x2
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E11'))
    OR (icd_version = 9 AND (
      REGEXP_CONTAINS(icd_code, r'^250[0-9]0') OR
      REGEXP_CONTAINS(icd_code, r'^250[0-9]2')
    ))
),
hf_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    -- ICD-10 I50.*, ICD-9 428.*
    (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
    OR (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428'))
),

-- 2. Admissions with both T2DM and HF
admissions_with_t2dm_hf AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Age and gender filter
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
    -- Must have both T2DM and HF
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN t2dm_icd t ON d.icd_code = t.icd_code AND d.icd_version = t.icd_version
      WHERE d.hadm_id = a.hadm_id
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN hf_icd h ON d.icd_code = h.icd_code AND d.icd_version = h.icd_version
      WHERE d.hadm_id = a.hadm_id
    )
),

-- 3. GLP-1 drug name list (injectable only)
glp1_drugs AS (
  SELECT 'exenatide' AS drug UNION ALL
  SELECT 'liraglutide' UNION ALL
  SELECT 'dulaglutide' UNION ALL
  SELECT 'semaglutide' UNION ALL
  SELECT 'lixisenatide'
),

-- 4. Find GLP-1 administrations in first 24h and final 48h
glp1_admins AS (
  -- EMAR (medication administration record)
  SELECT
    e.subject_id,
    e.hadm_id,
    e.charttime,
    LOWER(e.medication) AS drug,
    d.route
  FROM `physionet-data.mimiciv_3_1_hosp.emar` e
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` d
    ON e.subject_id = d.subject_id AND e.emar_id = d.emar_id AND e.emar_seq = d.emar_seq
  WHERE EXISTS (
    SELECT 1 FROM glp1_drugs g WHERE LOWER(e.medication) LIKE CONCAT('%', g.drug, '%')
  )
  AND (
    LOWER(d.route) LIKE '%sc%' OR LOWER(d.route) LIKE '%subcut%' OR LOWER(d.route) LIKE '%subcutaneous%'
    OR LOWER(d.route) LIKE '%inject%'
  )
  UNION ALL
  -- Pharmacy (dispensed, fallback if no EMAR)
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime AS charttime,
    LOWER(p.medication) AS drug,
    LOWER(p.route) AS route
  FROM `physionet-data.mimiciv_3_1_hosp.pharmacy` p
  WHERE EXISTS (
    SELECT 1 FROM glp1_drugs g WHERE LOWER(p.medication) LIKE CONCAT('%', g.drug, '%')
  )
  AND (
    LOWER(p.route) LIKE '%sc%' OR LOWER(p.route) LIKE '%subcut%' OR LOWER(p.route) LIKE '%subcutaneous%'
    OR LOWER(p.route) LIKE '%inject%'
  )
),

-- 5. For each admission, flag GLP-1 in first 24h and final 48h
admission_glp1_flags AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    -- First 24h window
    MAX(CASE WHEN ga.charttime >= a.admittime AND ga.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR) THEN 1 ELSE 0 END) AS glp1_first24h,
    -- Final 48h window
    MAX(CASE WHEN ga.charttime >= TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR) AND ga.charttime < a.dischtime THEN 1 ELSE 0 END) AS glp1_final48h
  FROM admissions_with_t2dm_hf a
  LEFT JOIN glp1_admins ga
    ON a.subject_id = ga.subject_id AND a.hadm_id = ga.hadm_id
  GROUP BY a.subject_id, a.hadm_id
),

-- 6. Aggregate prevalence
agg AS (
  SELECT
    COUNT(*) AS n_admissions,
    SUM(glp1_first24h) AS n_first24h,
    SUM(glp1_final48h) AS n_final48h
  FROM admission_glp1_flags
)

-- 7. Final output
SELECT
  n_admissions,
  n_first24h,
  n_final48h,
  SAFE_DIVIDE(n_first24h, n_admissions) * 100 AS prevalence_first24h_pct,
  SAFE_DIVIDE(n_final48h, n_admissions) * 100 AS prevalence_final48h_pct,
  SAFE_DIVIDE(n_final48h, n_admissions) * 100 - SAFE_DIVIDE(n_first24h, n_admissions) * 100 AS absolute_change_pct,
  CASE WHEN n_first24h > 0 THEN
    (SAFE_DIVIDE(n_final48h, n_admissions) - SAFE_DIVIDE(n_first24h, n_admissions)) / SAFE_DIVIDE(n_first24h, n_admissions)
  ELSE NULL END AS relative_change
FROM agg;