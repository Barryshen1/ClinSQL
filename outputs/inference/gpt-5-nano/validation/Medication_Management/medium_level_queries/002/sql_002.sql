WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    ((EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64)) + CAST(p.anchor_age AS INT64)) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    UPPER(p.gender) = 'F'
    AND ((EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64)) + CAST(p.anchor_age AS INT64)) BETWEEN 59 AND 69
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
)

SELECT
  COUNT(*) AS total_cohort,
  SUM(glp1_first48) AS n_glp1_first48,
  SAFE_DIVIDE(SUM(glp1_first48), COUNT(*)) AS p_glp1_first48,
  SUM(glp1_last12) AS n_glp1_last12,
  SAFE_DIVIDE(SUM(glp1_last12), COUNT(*)) AS p_glp1_last12,
  ABS(SAFE_DIVIDE(SUM(glp1_first48), COUNT(*)) - SAFE_DIVIDE(SUM(glp1_last12), COUNT(*))) AS abs_pp_diff
FROM (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.age_at_adm,
    -- GLP-1 use in first 48h window
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        WHERE pr.subject_id = c.subject_id
          AND pr.hadm_id = c.hadm_id
          AND (
            LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' OR
            LOWER(pr.drug) LIKE '%dulaglutide%' OR LOWER(pr.drug) LIKE '%lixisenatide%' OR
            LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%albiglutide%'
          )
          AND (
            LOWER(pr.route) LIKE '%subcutaneous%' OR LOWER(pr.route) LIKE '%injection%' OR
            LOWER(pr.route) LIKE '%intramuscular%' OR LOWER(pr.route) LIKE '%sc%' OR LOWER(pr.route) LIKE '%im%'
          )
          AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
      ),
      1, 0
    ) AS glp1_first48,
    -- GLP-1 use in last 12h window
    IF(
      EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
        WHERE pr.subject_id = c.subject_id
          AND pr.hadm_id = c.hadm_id
          AND (
            LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' OR
            LOWER(pr.drug) LIKE '%dulaglutide%' OR LOWER(pr.drug) LIKE '%lixisenatide%' OR
            LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%albiglutide%'
          )
          AND (
            LOWER(pr.route) LIKE '%subcutaneous%' OR LOWER(pr.route) LIKE '%injection%' OR
            LOWER(pr.route) LIKE '%intramuscular%' OR LOWER(pr.route) LIKE '%sc%' OR LOWER(pr.route) LIKE '%im%'
          )
          AND pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime
      ),
      1, 0
    ) AS glp1_last12
  FROM cohort c
) t;