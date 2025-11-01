WITH
  -- Step 1: Identify the cohort of admissions based on demographics, admission length, and diagnoses.
  filtered_cohort AS (
    SELECT
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
      ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 75 AND 85
      AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL
      AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 36
    GROUP BY
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    HAVING
      -- Condition 1: At least one diagnosis for Diabetes
      COUNT(DISTINCT CASE
        WHEN dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '250'
          THEN dx.icd_code
        WHEN dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) IN ('E08', 'E09', 'E10', 'E11', 'E13')
          THEN dx.icd_code
      END) > 0
      AND
      -- Condition 2: At least one diagnosis for Heart Failure
      COUNT(DISTINCT CASE
        WHEN dx.icd_version = 9 AND SUBSTR(dx.icd_code, 1, 3) = '428'
          THEN dx.icd_code
        WHEN dx.icd_version = 10 AND SUBSTR(dx.icd_code, 1, 3) = 'I50'
          THEN dx.icd_code
      END) > 0
  ),

  -- Step 2: Find the first start time of an injectable GLP-1 for each admission.
  glp1_starts AS (
    SELECT
      hadm_id,
      MIN(starttime) AS first_glp1_starttime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
      -- Filter for common injectable GLP-1 agonists
      (
        LOWER(drug) LIKE '%liraglutide%'
        OR LOWER(drug) LIKE '%semaglutide%'
        OR LOWER(drug) LIKE '%dulaglutide%'
        OR LOWER(drug) LIKE '%exenatide%'
        OR LOWER(drug) LIKE '%lixisenatide%'
        OR LOWER(drug) LIKE '%tirzepatide%'
      )
      -- Filter for injectable routes by excluding common oral routes
      AND UPPER(route) NOT IN ('PO', 'PO/NG')
      AND route IS NOT NULL
    GROUP BY
      hadm_id
  )

-- Step 3: Join the cohort with GLP-1 starts and calculate the final percentages.
SELECT
  -- Percentage of cohort admissions where a GLP-1 was started in the first 24 hours.
  ROUND(SAFE_DIVIDE(
    COUNT(
      CASE
        WHEN
          DATETIME_DIFF(g.first_glp1_starttime, fc.admittime, HOUR) >= 0
          AND DATETIME_DIFF(g.first_glp1_starttime, fc.admittime, HOUR) <= 24
          THEN fc.hadm_id
      END
    ) * 100.0,
    COUNT(fc.hadm_id)
  ), 2) AS pct_started_first_24h,

  -- Percentage of cohort admissions where a GLP-1 was started in the final 12 hours
  -- AND was NOT started in the first 24 hours.
  ROUND(SAFE_DIVIDE(
    COUNT(
      CASE
        WHEN
          NOT (
            DATETIME_DIFF(g.first_glp1_starttime, fc.admittime, HOUR) >= 0
            AND DATETIME_DIFF(g.first_glp1_starttime, fc.admittime, HOUR) <= 24
          )
          AND DATETIME_DIFF(fc.dischtime, g.first_glp1_starttime, HOUR) >= 0
          AND DATETIME_DIFF(fc.dischtime, g.first_glp1_starttime, HOUR) <= 12
          THEN fc.hadm_id
      END
    ) * 100.0,
    COUNT(fc.hadm_id)
  ), 2) AS pct_started_final_12h
FROM filtered_cohort AS fc
LEFT JOIN glp1_starts AS g
  ON fc.hadm_id = g.hadm_id;