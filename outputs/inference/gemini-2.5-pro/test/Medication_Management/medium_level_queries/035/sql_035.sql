WITH
  diagnosed_cohort AS (
    -- Step 1: Identify hospital admissions for female patients aged 57-67
    -- with diagnoses of both diabetes and heart failure.
    SELECT
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat ON adm.subject_id = pat.subject_id
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx ON adm.hadm_id = dx.hadm_id
    WHERE
      pat.gender = 'F'
      AND pat.anchor_age BETWEEN 57 AND 67
      AND adm.dischtime IS NOT NULL
    GROUP BY
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    HAVING
      -- At least one diagnosis code for Diabetes
      SUM(
        CASE
          WHEN dx.icd_code LIKE '250%' OR dx.icd_code LIKE 'E08%' OR dx.icd_code LIKE 'E09%' OR dx.icd_code LIKE 'E10%' OR dx.icd_code LIKE 'E11%' OR dx.icd_code LIKE 'E13%'
            THEN 1
          ELSE 0
        END
      ) > 0
      -- And at least one diagnosis code for Heart Failure
      AND SUM(
        CASE
          WHEN dx.icd_code LIKE '428%' OR dx.icd_code LIKE 'I50%'
            THEN 1
          ELSE 0
        END
      ) > 0
  ),
  glp1_prescriptions AS (
    -- Step 2: Identify all GLP-1 RA prescriptions from the prescriptions table
    SELECT
      hadm_id,
      starttime
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
      LOWER(drug) LIKE '%semaglutide%'
      OR LOWER(drug) LIKE '%ozempic%'
      OR LOWER(drug) LIKE '%rybelsus%'
      OR LOWER(drug) LIKE '%liraglutide%'
      OR LOWER(drug) LIKE '%victoza%'
      OR LOWER(drug) LIKE '%dulaglutide%'
      OR LOWER(drug) LIKE '%trulicity%'
      OR LOWER(drug) LIKE '%exenatide%'
      OR LOWER(drug) LIKE '%byetta%'
      OR LOWER(drug) LIKE '%bydureon%'
      OR LOWER(drug) LIKE '%lixisenatide%'
      OR LOWER(drug) LIKE '%adlyxin%'
  ),
  cohort_with_flags AS (
    -- Step 3: For each admission in the cohort, flag if a GLP-1 RA was prescribed
    -- in the first 48h or final 12h of the stay.
    SELECT
      dc.hadm_id,
      MAX(
        CASE
          WHEN gp.starttime BETWEEN dc.admittime AND DATETIME_ADD(dc.admittime, INTERVAL 48 HOUR)
            THEN 1
          ELSE 0
        END
      ) AS prescribed_first_48h,
      MAX(
        CASE
          WHEN gp.starttime BETWEEN DATETIME_SUB(dc.dischtime, INTERVAL 12 HOUR) AND dc.dischtime
            THEN 1
          ELSE 0
        END
      ) AS prescribed_final_12h
    FROM
      diagnosed_cohort AS dc
      LEFT JOIN glp1_prescriptions AS gp ON dc.hadm_id = gp.hadm_id
    GROUP BY
      dc.hadm_id
  ),
  summary_stats AS (
    -- Step 4: Calculate total cohort size and counts for each window
    SELECT
      COUNT(hadm_id) AS total_admissions,
      SUM(prescribed_first_48h) AS count_prescribed_first_48h,
      SUM(prescribed_final_12h) AS count_prescribed_final_12h
    FROM
      cohort_with_flags
  )
-- Step 5: Calculate final prevalence percentages and the absolute/relative change
SELECT
  s.total_admissions,
  s.count_prescribed_first_48h,
  s.count_prescribed_final_12h,
  SAFE_DIVIDE(s.count_prescribed_first_48h, s.total_admissions) * 100 AS prevalence_first_48h_pct,
  SAFE_DIVIDE(s.count_prescribed_final_12h, s.total_admissions) * 100 AS prevalence_final_12h_pct,
  (
    SAFE_DIVIDE(s.count_prescribed_final_12h, s.total_admissions) * 100
  ) - (
    SAFE_DIVIDE(s.count_prescribed_first_48h, s.total_admissions) * 100
  ) AS absolute_change_in_prevalence_pct,
  SAFE_DIVIDE(
    (
      SAFE_DIVIDE(s.count_prescribed_final_12h, s.total_admissions) * 100
    ) - (
      SAFE_DIVIDE(s.count_prescribed_first_48h, s.total_admissions) * 100
    ),
    SAFE_DIVIDE(s.count_prescribed_first_48h, s.total_admissions) * 100
  ) * 100 AS relative_change_in_prevalence_pct
FROM
  summary_stats AS s;