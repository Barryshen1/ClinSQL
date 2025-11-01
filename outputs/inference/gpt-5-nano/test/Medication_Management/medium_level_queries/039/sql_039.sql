WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE LOWER(p.gender) IN ('m', 'male')
    AND p.anchor_age BETWEEN 52 AND 62
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (LOWER(dd.long_title) LIKE '%type 2 diabetes%' OR
             LOWER(dd.long_title) LIKE '%diabetes mellitus type 2%')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (LOWER(dd.long_title) LIKE '%heart failure%' OR
             LOWER(dd.long_title) LIKE '%congestive heart failure%')
    )
),
glp1_flags AS (
  SELECT
    c.hadm_id,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = c.subject_id
        AND pr.hadm_id = c.hadm_id
        AND pr.starttime >= c.admittime
        AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
        AND (
          LOWER(pr.drug) LIKE '%liraglutide%' OR
          LOWER(pr.drug) LIKE '%exenatide%' OR
          LOWER(pr.drug) LIKE '%dulaglutide%' OR
          LOWER(pr.drug) LIKE '%semaglutide%' OR
          LOWER(pr.drug) LIKE '%lixisenatide%'
        )
    ) AS has_first24,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = c.subject_id
        AND pr.hadm_id = c.hadm_id
        AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
        AND pr.starttime <= c.dischtime
        AND (
          LOWER(pr.drug) LIKE '%liraglutide%' OR
          LOWER(pr.drug) LIKE '%exenatide%' OR
          LOWER(pr.drug) LIKE '%dulaglutide%' OR
          LOWER(pr.drug) LIKE '%semaglutide%' OR
          LOWER(pr.drug) LIKE '%lixisenatide%'
        )
    ) AS has_last48
  FROM cohort c
)
SELECT
  COUNT(*) AS total_cohort,
  ROUND(SAFE_DIVIDE(SUM(IF(has_first24, 1, 0)), COUNT(*)) * 100, 2) AS prevalence_first24_percent,
  ROUND(SAFE_DIVIDE(SUM(IF(has_last48, 1, 0)), COUNT(*)) * 100, 2) AS prevalence_final48_percent,
  ROUND(ABS((SAFE_DIVIDE(SUM(IF(has_last48, 1, 0)), COUNT(*)) - SAFE_DIVIDE(SUM(IF(has_first24, 1, 0)), COUNT(*))) * 100), 2) AS abs_change_percent_points,
  CASE
    WHEN SAFE_DIVIDE(SUM(IF(has_first24, 1, 0)), COUNT(*)) > 0
    THEN ROUND(
           ((SAFE_DIVIDE(SUM(IF(has_last48, 1, 0)), COUNT(*)) - SAFE_DIVIDE(SUM(IF(has_first24, 1, 0)), COUNT(*)))
            / SAFE_DIVIDE(SUM(IF(has_first24, 1, 0)), COUNT(*))
           ) * 100, 2)
    ELSE NULL
  END AS relative_change_percent
FROM glp1_flags;