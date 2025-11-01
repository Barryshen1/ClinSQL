WITH
-- Get male pneumonia admissions for 95-year-olds
pneumonia_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 95
    AND d.icd_code LIKE 'J18.%'  -- ICD-10 code for pneumonia
),

-- Get peak creatinine per admission
peak_creatinine AS (
  SELECT
    pa.hadm_id,
    MAX(le.valuenum) AS peak_creatinine
  FROM
    pneumonia_admissions pa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON pa.hadm_id = le.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Creatinine, Serum'  -- or use itemid = 50912 directly
    AND le.valuenum IS NOT NULL
  GROUP BY
    pa.hadm_id
)

-- Calculate standard deviation of peak creatinine
SELECT
  STDDEV(peak_creatinine.peak_creatinine) AS stddev_peak_creatinine
FROM
  peak_creatinine;