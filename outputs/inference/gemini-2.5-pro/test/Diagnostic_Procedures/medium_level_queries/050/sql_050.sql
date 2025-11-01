WITH
  -- Step 1: Identify relevant hospital admissions for male patients aged 90-100 and categorize their length of stay.
  patient_stays AS (
    SELECT
      adm.hadm_id,
      CASE
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 BETWEEN 1 AND 3
          THEN '1-3 day stays'
        WHEN DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 BETWEEN 4 AND 7
          THEN '4-7 day stays'
        ELSE NULL
      END AS los_category
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON adm.subject_id = pat.subject_id
    WHERE
      pat.gender = 'M'
      AND pat.anchor_age BETWEEN 90 AND 100
      AND adm.dischtime IS NOT NULL AND adm.admittime IS NOT NULL
  ),

  -- Step 2: For each admission in the cohort, count the number of diagnostic imaging procedures.
  -- Diagnostic imaging is defined using ICD-9 codes (87-88) and ICD-10 codes (starting with 'B').
  admission_procedure_counts AS (
    SELECT
      ps.hadm_id,
      ps.los_category,
      COUNT(proc.icd_code) AS num_imaging_procedures
    FROM patient_stays AS ps
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      ON ps.hadm_id = proc.hadm_id
      AND (
        (proc.icd_version = 9 AND SUBSTR(proc.icd_code, 1, 2) BETWEEN '87' AND '88')
        OR (proc.icd_version = 10 AND proc.icd_code LIKE 'B%')
      )
    WHERE
      ps.los_category IS NOT NULL -- Exclude stays that are not 1-3 or 4-7 days
    GROUP BY
      ps.hadm_id,
      ps.los_category
  )

-- Step 3: Aggregate the procedure counts to get the mean, min, and max for each stay category.
SELECT
  los_category,
  AVG(num_imaging_procedures) AS mean_imaging_procedures,
  MIN(num_imaging_procedures) AS min_imaging_procedures,
  MAX(num_imaging_procedures) AS max_imaging_procedures
FROM admission_procedure_counts
GROUP BY
  los_category
ORDER BY
  los_category;