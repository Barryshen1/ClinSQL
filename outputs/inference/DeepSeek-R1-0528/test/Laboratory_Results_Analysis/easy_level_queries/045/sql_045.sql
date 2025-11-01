WITH sepsis_male_admissions AS (
  SELECT DISTINCT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'M'
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '995.91%')
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '995.92%')
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '785.52%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'A41%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'R65.20%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'R65.21%')
    )
),
first_creatinine_time AS (
  SELECT
    l.hadm_id,
    MIN(l.charttime) AS first_charttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN
    sepsis_male_admissions adm
    ON l.hadm_id = adm.hadm_id
  WHERE
    l.itemid = 50912  -- Serum Creatinine
    AND l.charttime BETWEEN adm.admittime AND adm.dischtime
  GROUP BY
    l.hadm_id
),
max_creatinine_at_first_time AS (
  SELECT
    l.hadm_id,
    MAX(l.valuenum) AS creatinine_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN
    first_creatinine_time f
    ON l.hadm_id = f.hadm_id
    AND l.charttime = f.first_charttime
  WHERE
    l.itemid = 50912
  GROUP BY
    l.hadm_id
)
SELECT
  MAX(creatinine_value) AS max_index_creatinine
FROM
  max_creatinine_at_first_time;