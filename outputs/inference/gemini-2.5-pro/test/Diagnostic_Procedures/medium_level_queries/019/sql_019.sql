WITH
  ap_hadm AS (
    -- Identify hospital admissions (hadm_id) for acute pancreatitis
    SELECT DISTINCT
      dx.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddx
      ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
    WHERE
      LOWER(ddx.long_title) LIKE '%acute pancreatitis%'
  ),
  proc_counts AS (
    -- Count the number of ICD procedures for each admission
    SELECT
      hadm_id,
      COUNT(icd_code) AS num_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    GROUP BY
      hadm_id
  ),
  cohort AS (
    -- Build the primary cohort by filtering patients by diagnosis, demographics, and joining procedure counts
    SELECT
      p.subject_id,
      a.hadm_id,
      -- Calculate length of stay (LOS) in days, rounding up. Minimum LOS is 1 day.
      GREATEST(
        1,
        CAST(
          CEIL(
            DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0
          ) AS INT64
        )
      ) AS los_days,
      COALESCE(pc.num_procedures, 0) AS num_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    INNER JOIN ap_hadm
      ON a.hadm_id = ap_hadm.hadm_id
    LEFT JOIN proc_counts AS pc
      ON a.hadm_id = pc.hadm_id
    WHERE
      p.gender = 'M'
      AND (
        DATETIME_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) + p.anchor_age
      ) BETWEEN 42 AND 52
      AND a.dischtime IS NOT NULL
  ),
  cohort_los AS (
    -- Assign LOS categories to the cohort
    SELECT
      subject_id,
      num_procedures,
      CASE
        WHEN los_days BETWEEN 1 AND 4
        THEN '1-4 days'
        WHEN los_days BETWEEN 5 AND 7
        THEN '5-7 days'
        ELSE NULL
      END AS los_category
    FROM cohort
  )
-- Final aggregation and formatting
SELECT
  los_category,
  COUNT(DISTINCT subject_id) AS patient_count,
  FORMAT(
    '%.2f (%d-%d)',
    AVG(num_procedures),
    MIN(num_procedures),
    MAX(num_procedures)
  ) AS procedures_mean_min_max
FROM cohort_los
WHERE
  los_category IS NOT NULL
GROUP BY
  los_category
ORDER BY
  los_category;