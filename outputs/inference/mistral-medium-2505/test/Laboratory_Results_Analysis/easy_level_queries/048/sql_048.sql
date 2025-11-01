WITH
-- Get women aged 56 with COPD
copd_patients AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 56
    AND (di.icd_code LIKE '496.%' OR di.icd_code LIKE 'J44.%') -- COPD codes
),

-- Get creatinine measurements in first 24h
creatinine_24h AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    AVG(l.valuenum) AS avg_creatinine
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON l.itemid = dl.itemid
  JOIN
    copd_patients c
    ON l.subject_id = c.subject_id AND l.hadm_id = c.hadm_id
  WHERE
    dl.label = 'Creatinine'
    AND l.charttime BETWEEN c.admittime
      AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
    AND l.valuenum IS NOT NULL
  GROUP BY
    l.subject_id, l.hadm_id
)

-- Compute 75th percentile of average creatinine
SELECT
  PERCENTILE_CONT(avg_creatinine, 0.75) OVER() AS p75_creatinine
FROM
  creatinine_24h
LIMIT 1;