WITH
  diagnoses AS (
    -- Pre-aggregate diagnoses to flag admissions with T2DM and Heart Failure
    SELECT
      hadm_id,
      MAX(
        CASE
          WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '250'
            THEN 1
          WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'E11'
            THEN 1
          ELSE 0
        END
      ) AS has_t2dm,
      MAX(
        CASE
          WHEN icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '428'
            THEN 1
          WHEN icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'I50'
            THEN 1
          ELSE 0
        END
      ) AS has_hf
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    GROUP BY
      hadm_id
  ),

  cohort AS (
    -- Identify the cohort of admissions meeting all criteria
    SELECT
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    INNER JOIN diagnoses AS d
      ON a.hadm_id = d.hadm_id
    WHERE
      p.gender = 'F'
      AND (
        DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR)
        + p.anchor_age
      ) BETWEEN 50 AND 60
      AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
      AND d.has_t2dm = 1
      AND d.has_hf = 1
  ),

  glp1_admins AS (
    -- Identify all GLP-1 administrations from the EMAR table
    SELECT
      hadm_id,
      charttime
    FROM `physionet-data.mimiciv_3_1_hosp.emar`
    WHERE
      LOWER(medication) LIKE '%semaglutide%'
      OR LOWER(medication) LIKE '%liraglutide%'
      OR LOWER(medication) LIKE '%dulaglutide%'
      OR LOWER(medication) LIKE '%exenatide%'
      OR LOWER(medication) LIKE '%lixisenatide%'
      OR LOWER(medication) LIKE '%ozempic%'
      OR LOWER(medication) LIKE '%rybelsus%'
      OR LOWER(medication) LIKE '%wegovy%'
      OR LOWER(medication) LIKE '%victoza%'
      OR LOWER(medication) LIKE '%trulicity%'
      OR LOWER(medication) LIKE '%byetta%'
  ),

  admission_metrics AS (
    -- For each admission in the cohort, determine if they meet the initiation and prevalence criteria
    SELECT
      c.hadm_id,
      MAX(
        CASE
          WHEN g.charttime <= DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS initial_admin_flag,
      MAX(
        CASE
          WHEN g.charttime >= DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS final_admin_flag
    FROM cohort AS c
    LEFT JOIN glp1_admins AS g
      ON c.hadm_id = g.hadm_id
    GROUP BY
      c.hadm_id,
      c.admittime,
      c.dischtime
  )

-- Final aggregation to calculate the requested percentages and change
SELECT
  COUNT(hadm_id) AS total_patients_in_cohort,
  SAFE_DIVIDE(SUM(initial_admin_flag), COUNT(hadm_id))
  * 100 AS first_12h_initiation_pct,
  SAFE_DIVIDE(SUM(final_admin_flag), COUNT(hadm_id))
  * 100 AS final_72h_prevalence_pct,
  (
    SAFE_DIVIDE(SUM(final_admin_flag), COUNT(hadm_id)) * 100
  ) - (
    SAFE_DIVIDE(SUM(initial_admin_flag), COUNT(hadm_id)) * 100
  ) AS net_percentage_point_change
FROM admission_metrics;