WITH
  -- Define cohort: male, age 57-67, with diabetes AND acute HF
  cohort AS (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` adm
      INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
        ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year BETWEEN 57 AND 67
      AND adm.hadm_id IN (
        -- Admissions with diabetes (corrected ICD-10 logic)
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
          (icd_version = 9 AND icd_code LIKE '250%') OR
          (icd_version = 10 AND (
            icd_code LIKE 'E10%' OR 
            icd_code LIKE 'E11%' OR 
            icd_code LIKE 'E12%' OR 
            icd_code LIKE 'E13%' OR 
            icd_code LIKE 'E14%'
          ))
      )
      AND adm.hadm_id IN (
        -- Admissions with acute HF
        SELECT hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
          (icd_version = 9 AND icd_code LIKE '428%') OR
          (icd_version = 10 AND icd_code LIKE 'I50%')
      )
  ),
  -- Identify GLP-1 prescriptions
  glp1_orders AS (
    SELECT
      hadm_id,
      starttime
    FROM
      `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE
      LOWER(drug) LIKE '%liraglutide%' OR
      LOWER(drug) LIKE '%exenatide%' OR
      LOWER(drug) LIKE '%dulaglutide%' OR
      LOWER(drug) LIKE '%semaglutide%' OR
      LOWER(drug) LIKE '%albiglutide%' OR
      LOWER(drug) LIKE '%lixisenatide%'
  ),
  -- Flag initiations in first 72h and final 24h
  cohort_flags AS (
    SELECT
      c.hadm_id,
      MAX(
        CASE WHEN g.starttime 
          BETWEEN c.admittime 
          AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
        THEN 1 ELSE 0 END
      ) AS glp1_first_72h,
      MAX(
        CASE WHEN g.starttime 
          BETWEEN GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR))
          AND c.dischtime
        THEN 1 ELSE 0 END
      ) AS glp1_final_24h
    FROM
      cohort c
      LEFT JOIN glp1_orders g 
        ON c.hadm_id = g.hadm_id
    GROUP BY
      c.hadm_id
  )
-- Calculate metrics
SELECT
  COUNT(*) AS total_admissions,
  SUM(glp1_first_72h) AS count_first_72h,
  SUM(glp1_final_24h) AS count_final_24h,
  ROUND(SUM(glp1_first_72h) * 100.0 / COUNT(*), 2) AS pct_first_72h,
  ROUND(SUM(glp1_final_24h) * 100.0 / COUNT(*), 2) AS pct_final_24h,
  ROUND(
    (SUM(glp1_final_24h) * 100.0 / COUNT(*)) - 
    (SUM(glp1_first_72h) * 100.0 / COUNT(*)), 
    2
  ) AS absolute_change,
  ROUND(
    ((SUM(glp1_final_24h) * 100.0 / COUNT(*)) - 
    (SUM(glp1_first_72h) * 100.0 / COUNT(*))) /
    NULLIF((SUM(glp1_first_72h) * 100.0 / COUNT(*)), 0) * 100, 
    2
  ) AS relative_change
FROM
  cohort_flags;