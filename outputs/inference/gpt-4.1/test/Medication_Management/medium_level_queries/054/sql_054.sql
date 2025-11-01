WITH cohort AS (
  -- Select male inpatients aged 56–66 with diabetes AND heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    -- Diabetes diagnosis
    JOIN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (
          (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250') OR
          (icd_version = 10 AND SUBSTR(icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E13'))
        )
      GROUP BY hadm_id
    ) d1 ON a.hadm_id = d1.hadm_id
    -- Heart failure diagnosis
    JOIN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (
          (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428') OR
          (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50')
        )
      GROUP BY hadm_id
    ) d2 ON a.hadm_id = d2.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 56 AND 66
),

glp1_drugs AS (
  -- List of GLP-1 receptor agonist drug names (lowercase for matching)
  SELECT 'exenatide' AS drug UNION ALL
  SELECT 'liraglutide' UNION ALL
  SELECT 'dulaglutide' UNION ALL
  SELECT 'semaglutide' UNION ALL
  SELECT 'albiglutide' UNION ALL
  SELECT 'lixisenatide'
),

presc_glp1 AS (
  -- All GLP-1 prescriptions for cohort admissions
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    pr.stoptime,
    LOWER(pr.drug) AS drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN cohort c ON pr.hadm_id = c.hadm_id
    JOIN glp1_drugs g ON LOWER(pr.drug) LIKE CONCAT('%', g.drug, '%')
),

window_flags AS (
  -- For each admission, flag GLP-1 use in first 48h and final 24h
  SELECT
    c.subject_id,
    c.hadm_id,
    -- First 48h window
    MAX(
      CASE
        WHEN
          presc_glp1.starttime >= c.admittime
          AND presc_glp1.starttime < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
        THEN 1 ELSE 0
      END
    ) AS glp1_first_48h,
    -- Final 24h window: prescription active at any time in last 24h
    MAX(
      CASE
        WHEN
          presc_glp1.starttime < c.dischtime
          AND presc_glp1.stoptime > DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR)
        THEN 1 ELSE 0
      END
    ) AS glp1_final_24h
  FROM
    cohort c
    LEFT JOIN presc_glp1
      ON c.hadm_id = presc_glp1.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id
),

summary AS (
  SELECT
    COUNT(*) AS n_admissions,
    SUM(glp1_first_48h) AS n_first_48h,
    SUM(glp1_final_24h) AS n_final_24h
  FROM window_flags
)

SELECT
  n_admissions,
  ROUND(100.0 * n_first_48h / n_admissions, 2) AS prevalence_first_48h_pct,
  ROUND(100.0 * n_final_24h / n_admissions, 2) AS prevalence_final_24h_pct,
  ROUND(100.0 * (n_final_24h - n_first_48h) / n_admissions, 2) AS net_change_pct
FROM summary;