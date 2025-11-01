with pop AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_year,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
    -- Diabetes diagnosis presence in the admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.subject_id = a.subject_id
        AND dx.hadm_id = a.hadm_id
        AND (
          (dx.icd_version = 9 AND dx.icd_code LIKE '250%')
          OR (dx.icd_version = 9 AND dx.icd_code LIKE '250.%')
          OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'E10%' OR dx.icd_code LIKE 'E11%' OR dx.icd_code LIKE 'E12%' OR dx.icd_code LIKE 'E13%' OR dx.icd_code LIKE 'E14%'))
        )
    )
    -- Acute HF diagnosis presence in the admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      WHERE dx.subject_id = a.subject_id
        AND dx.hadm_id = a.hadm_id
        AND (
          (dx.icd_version = 9 AND dx.icd_code LIKE '428%')
          OR (dx.icd_version = 10 AND dx.icd_code LIKE 'I50%')
        )
    )
)

, glp_window AS (
  SELECT
    p.hadm_id,
    MAX(CASE
          WHEN pr.starttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 72 HOUR)
               AND (
                 LOWER(pr.drug) LIKE '%liraglutide%' OR
                 LOWER(pr.drug) LIKE '%dulaglutide%' OR
                 LOWER(pr.drug) LIKE '%exenatide%' OR
                 LOWER(pr.drug) LIKE '%lixisenatide%' OR
                 LOWER(pr.drug) LIKE '%semaglutide%' OR
                 LOWER(pr.drug) LIKE '%albiglutide%'
               )
          THEN 1 ELSE 0 END
         ) AS glp72h,
    MAX(CASE
          WHEN pr.starttime BETWEEN TIMESTAMP_SUB(p.dischtime, INTERVAL 24 HOUR) AND p.dischtime
               AND (
                 LOWER(pr.drug) LIKE '%liraglutide%' OR
                 LOWER(pr.drug) LIKE '%dulaglutide%' OR
                 LOWER(pr.drug) LIKE '%exenatide%' OR
                 LOWER(pr.drug) LIKE '%lixisenatide%' OR
                 LOWER(pr.drug) LIKE '%semaglutide%' OR
                 LOWER(pr.drug) LIKE '%albiglutide%'
               )
          THEN 1 ELSE 0 END
         ) AS glp24h
  FROM pop p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.subject_id = p.subject_id AND pr.hadm_id = p.hadm_id
  GROUP BY p.hadm_id
)

SELECT
  COUNT(*) AS total_population,
  SAFE_DIVIDE(SUM(glp72h), COUNT(*)) * 100 AS prevalence_72h_percent,
  SAFE_DIVIDE(SUM(glp24h), COUNT(*)) * 100 AS prevalence_final24h_percent,
  SAFE_DIVIDE(SUM(glp72h), COUNT(*)) * 100 AS initiation_72h_percent,
  SAFE_DIVIDE(SUM(glp24h), COUNT(*)) * 100 AS initiation_final24h_percent,
  ((SAFE_DIVIDE(SUM(glp24h), COUNT(*)) - SAFE_DIVIDE(SUM(glp72h), COUNT(*))) * 100) AS abs_change_prevalence_percent,
  CASE
    WHEN SAFE_DIVIDE(SUM(glp72h), COUNT(*)) = 0 THEN NULL
    ELSE ((SAFE_DIVIDE(SUM(glp24h), COUNT(*)) - SAFE_DIVIDE(SUM(glp72h), COUNT(*)))
          / SAFE_DIVIDE(SUM(glp72h), COUNT(*)))
          * 100
  END AS rel_change_prevalence_percent,
  ((SAFE_DIVIDE(SUM(glp24h), COUNT(*)) - SAFE_DIVIDE(SUM(glp72h), COUNT(*))) * 100) AS abs_change_initiation_percent,
  CASE
    WHEN SAFE_DIVIDE(SUM(glp72h), COUNT(*)) = 0 THEN NULL
    ELSE ((SAFE_DIVIDE(SUM(glp24h), COUNT(*)) - SAFE_DIVIDE(SUM(glp72h), COUNT(*)))
          / SAFE_DIVIDE(SUM(glp72h), COUNT(*)))
          * 100
  END AS rel_change_initiation_percent
FROM glp_window;