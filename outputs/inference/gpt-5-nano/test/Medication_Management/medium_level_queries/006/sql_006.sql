WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) IN ('female', 'f')
    AND p.anchor_age BETWEEN 48 AND 58
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dHF
      WHERE dHF.subject_id = a.subject_id
        AND dHF.hadm_id = a.hadm_id
        AND dHF.icd_version = 10
        AND dHF.icd_code LIKE 'I50%'
    )
),
flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- Flag: GLP-1 initiation within first 72 hours
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = c.subject_id
        AND pr.hadm_id = c.hadm_id
        AND pr.starttime >= c.admittime
        AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
        AND (
          LOWER(pr.drug) LIKE '%liraglutide%'   OR
          LOWER(pr.drug) LIKE '%dulaglutide%'  OR
          LOWER(pr.drug) LIKE '%exenatide%'    OR
          LOWER(pr.drug) LIKE '%semaglutide%'  OR
          LOWER(pr.drug) LIKE '%lixisenatide%' OR
          LOWER(pr.drug) LIKE '%albiglutide%'
        )
    ) THEN 1 ELSE 0 END AS first72_flag,
    -- Flag: GLP-1 initiation within last 48 hours of discharge
    CASE WHEN c.dischtime IS NOT NULL AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = c.subject_id
        AND pr.hadm_id = c.hadm_id
        AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
        AND pr.starttime <= c.dischtime
        AND (
          LOWER(pr.drug) LIKE '%liraglutide%'   OR
          LOWER(pr.drug) LIKE '%dulaglutide%'  OR
          LOWER(pr.drug) LIKE '%exenatide%'    OR
          LOWER(pr.drug) LIKE '%semaglutide%'  OR
          LOWER(pr.drug) LIKE '%lixisenatide%' OR
          LOWER(pr.drug) LIKE '%albiglutide%'
        )
    ) THEN 1 ELSE 0 END AS last48_flag
  FROM cohort c
)
SELECT
  COUNT(*) AS total_cohort,
  SUM(first72_flag) AS n_first72,
  SUM(last48_flag) AS n_last48,
  SAFE_DIVIDE(SUM(first72_flag), COUNT(*)) * 100 AS rate_first72_pct,
  SAFE_DIVIDE(SUM(last48_flag), COUNT(*)) * 100 AS rate_last48_pct,
  ABS(
    SAFE_DIVIDE(SUM(first72_flag), COUNT(*)) * 100
    - SAFE_DIVIDE(SUM(last48_flag), COUNT(*)) * 100
  ) AS abs_difference_pp
FROM flags;