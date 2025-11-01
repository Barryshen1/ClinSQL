WITH
  hadm_with_diagnoses AS (
    -- This CTE identifies hospital admissions with both Type 2 Diabetes and Heart Failure diagnoses.
    SELECT
      dx.hadm_id,
      MAX(
        CASE
          WHEN
            -- ICD-9 codes for Type 2 Diabetes
            (
              dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '250' AND (SUBSTR(dx.icd_code, 5, 1) = '0' OR SUBSTR(dx.icd_code, 5, 1) = '2')
            )
            -- ICD-10 codes for Type 2 Diabetes
            OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) = 'E11')
            THEN 1
          ELSE 0
        END
      ) AS has_t2d,
      MAX(
        CASE
          WHEN
            -- ICD-9 codes for Heart Failure
            (dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '428')
            -- ICD-10 codes for Heart Failure
            OR (dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) = 'I50')
            THEN 1
          ELSE 0
        END
      ) AS has_hf
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    GROUP BY
      dx.hadm_id
  ),
  cohort AS (
    -- This CTE establishes the final patient cohort based on demographics and diagnoses.
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN hadm_with_diagnoses AS dx
      ON a.hadm_id = dx.hadm_id
    WHERE
      p.gender = 'M'
      AND p.anchor_age BETWEEN 79 AND 89
      AND dx.has_t2d = 1
      AND dx.has_hf = 1
      -- Ensure admission and discharge times are valid for window calculation
      AND a.admittime IS NOT NULL
      AND a.dischtime IS NOT NULL
  ),
  first_glp1_admin AS (
    -- This CTE finds the first administration time of a GLP-1 for each hospital admission.
    SELECT
      e.hadm_id,
      MIN(e.charttime) AS first_admin_time
    FROM `physionet-data.mimiciv_3_1_hosp.emar` AS e
    -- Filter for GLP-1 receptor agonists by generic and brand names
    WHERE
      (
        LOWER(e.medication) LIKE '%liraglutide%'
        OR LOWER(e.medication) LIKE '%semaglutide%'
        OR LOWER(e.medication) LIKE '%dulaglutide%'
        OR LOWER(e.medication) LIKE '%exenatide%'
        OR LOWER(e.medication) LIKE '%lixisenatide%'
        OR LOWER(e.medication) LIKE '%victoza%'
        OR LOWER(e.medication) LIKE '%ozempic%'
        OR LOWER(e.medication) LIKE '%rybelsus%'
        OR LOWER(e.medication) LIKE '%trulicity%'
        OR LOWER(e.medication) LIKE '%byetta%'
        OR LOWER(e.medication) LIKE '%bydureon%'
      )
      -- Only consider actual administrations, not held or refused doses
      AND e.event_txt = 'Administered'
    GROUP BY
      e.hadm_id
  ),
  categorized_cohort AS (
    -- This CTE joins the cohort with initiation events and categorizes them into the time windows.
    SELECT
      c.hadm_id,
      -- Flag is 1 if the first administration is within the first 12 hours of admission
      CASE
        WHEN
          f.first_admin_time >= c.admittime
          AND f.first_admin_time < DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
          THEN 1
        ELSE 0
      END AS initiated_first_12h,
      -- Flag is 1 if the first administration is within the final 24 hours before discharge
      CASE
        WHEN
          f.first_admin_time >= DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR)
          AND f.first_admin_time <= c.dischtime
          THEN 1
        ELSE 0
      END AS initiated_last_24h
    FROM cohort AS c
    LEFT JOIN first_glp1_admin AS f
      ON c.hadm_id = f.hadm_id
  )
-- Final calculation and presentation of the results
SELECT
  COUNT(*) AS total_eligible_patients,
  SUM(initiated_first_12h) AS count_initiated_first_12h,
  SUM(initiated_last_24h) AS count_initiated_last_24h,
  ROUND(100.0 * SUM(initiated_first_12h) / COUNT(*), 2) AS percent_initiated_first_12h,
  ROUND(100.0 * SUM(initiated_last_24h) / COUNT(*), 2) AS percent_initiated_last_24h,
  ROUND(
    (100.0 * SUM(initiated_last_24h) / COUNT(*)) - (100.0 * SUM(initiated_first_12h) / COUNT(*)),
    2
  ) AS net_percentage_point_change
FROM categorized_cohort;