WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
    AND a.subject_id = diag.subject_id
  WHERE
    p.anchor_age = 90
    AND p.gender = 'M'
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '491%')
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '492%')
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '496%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'J44%')
    )
),
creatinine_avg AS (
  SELECT
    c.hadm_id,
    AVG(l.valuenum) AS avg_creatinine
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND c.subject_id = l.subject_id
  WHERE
    l.itemid = 50912  -- Serum Creatinine
    AND l.charttime >= c.admittime
    AND l.charttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND l.valuenum IS NOT NULL  -- Ensure numeric value
  GROUP BY c.hadm_id
)
SELECT
  STDDEV(avg_creatinine) AS std_dev_creatinine_avg
FROM creatinine_avg;