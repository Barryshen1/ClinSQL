WITH
-- Get 90-year-old males with COPD
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
  WHERE
    p.anchor_age = 90
    AND p.gender = 'M'
    AND d.icd_code IN ('J449', 'J44.9') -- COPD ICD-10 codes
),

-- Get creatinine measurements in the first 24 hours
creatinine_24h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.charttime,
    c.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` l
    ON c.itemid = l.itemid
  JOIN
    copd_patients p
    ON c.subject_id = p.subject_id AND c.hadm_id = p.hadm_id
  WHERE
    l.label = 'Creatinine'
    AND c.charttime BETWEEN p.admittime
      AND TIMESTAMP_ADD(p.admittime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
),

-- Calculate average creatinine per patient per admission
avg_creatinine AS (
  SELECT
    subject_id,
    hadm_id,
    AVG(valuenum) AS avg_creatinine
  FROM
    creatinine_24h
  GROUP BY
    subject_id, hadm_id
)

-- Compute standard deviation of the averages
SELECT
  STDDEV(avg_creatinine) AS stddev_creatinine_24h
FROM
  avg_creatinine;