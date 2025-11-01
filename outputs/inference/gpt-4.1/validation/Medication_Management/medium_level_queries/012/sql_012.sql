WITH cohort AS (
  -- Select admissions for females aged 50-60, admitted >=72h, with both T2DM and HF
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND a.hadm_id IN (
      -- Must have BOTH T2DM and HF diagnoses
      SELECT hadm_id
      FROM (
        SELECT
          hadm_id,
          MAX(CASE WHEN
            ( (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^250[.]([0-9]{1,2})[02]?$')) OR
              (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^E11')) )
            THEN 1 ELSE 0 END) AS has_t2dm,
          MAX(CASE WHEN
            ( (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428')) OR
              (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50')) )
            THEN 1 ELSE 0 END) AS has_hf
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
        GROUP BY hadm_id
      )
      WHERE has_t2dm = 1 AND has_hf = 1
    )
),
glp1_drugs AS (
  -- List of GLP-1 drugs for matching
  SELECT 'exenatide' AS drug UNION ALL
  SELECT 'liraglutide' UNION ALL
  SELECT 'dulaglutide' UNION ALL
  SELECT 'semaglutide' UNION ALL
  SELECT 'albiglutide' UNION ALL
  SELECT 'lixisenatide'
),
glp1_presc AS (
  -- Find GLP-1 prescriptions in first 72h and first 12h
  SELECT
    c.subject_id,
    c.hadm_id,
    MIN(CASE WHEN TIMESTAMP_DIFF(pr.starttime, c.admittime, HOUR) < 12 THEN 1 ELSE 0 END) AS glp1_in_12h,
    MAX(CASE WHEN TIMESTAMP_DIFF(pr.starttime, c.admittime, HOUR) < 72 THEN 1 ELSE 0 END) AS glp1_in_72h
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  JOIN
    glp1_drugs g
    ON LOWER(pr.drug) LIKE CONCAT('%', g.drug, '%')
  WHERE
    pr.starttime >= c.admittime
    AND pr.starttime < c.dischtime
  GROUP BY
    c.subject_id, c.hadm_id
),
final AS (
  -- Merge cohort and GLP-1 prescription flags
  SELECT
    c.subject_id,
    c.hadm_id,
    IFNULL(g.glp1_in_12h, 0) AS glp1_in_12h,
    IFNULL(g.glp1_in_72h, 0) AS glp1_in_72h
  FROM
    cohort c
  LEFT JOIN
    glp1_presc g
    ON c.subject_id = g.subject_id AND c.hadm_id = g.hadm_id
)
SELECT
  COUNT(*) AS n_admissions,
  ROUND(SUM(glp1_in_12h) / COUNT(*) * 100, 2) AS first_12h_initiation_pct,
  ROUND(SUM(glp1_in_72h) / COUNT(*) * 100, 2) AS final_72h_prevalence_pct,
  ROUND(SUM(glp1_in_72h) / COUNT(*) * 100 - SUM(glp1_in_12h) / COUNT(*) * 100, 2) AS net_pct_point_change
FROM
  final
;