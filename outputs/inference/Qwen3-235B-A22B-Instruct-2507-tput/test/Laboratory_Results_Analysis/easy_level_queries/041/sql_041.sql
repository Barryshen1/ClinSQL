WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    -- Compute age at admission
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 45 AND 55
),
pneumonia_admissions AS (
  SELECT DISTINCT
    pa.hadm_id
  FROM
    patient_admissions pa
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON
    pa.hadm_id = di.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON
    di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%pneumonia%'
),
creatinine_values AS (
  SELECT
    le.hadm_id,
    le.valuenum,
    le.charttime
  FROM
    `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
  ON
    le.itemid = dl.itemid
  WHERE
    LOWER(dl.label) = 'creatinine'
    AND LOWER(dl.fluid) = 'blood'
    AND le.valuenum IS NOT NULL
),
creatinine_first_24h AS (
  SELECT
    cv.hadm_id,
    AVG(cv.valuenum) AS avg_creatinine_24h
  FROM
    creatinine_values cv
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    cv.hadm_id = a.hadm_id
  WHERE
    cv.charttime >= a.admittime
    AND cv.charttime < DATETIME_ADD(a.admittime, INTERVAL 24 HOUR)
  GROUP BY
    cv.hadm_id
)
SELECT
  STDDEV(c.avg_creatinine_24h) AS sd_avg_creatinine_first_24h
FROM
  creatinine_first_24h c
INNER JOIN
  pneumonia_admissions pa
ON
  c.hadm_id = pa.hadm_id;