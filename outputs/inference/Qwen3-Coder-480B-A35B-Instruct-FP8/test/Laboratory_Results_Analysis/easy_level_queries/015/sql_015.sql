WITH pneumonia_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'F'
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
),
creatinine_labs AS (
  SELECT
    l.hadm_id,
    l.valuenum
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  JOIN
    pneumonia_admissions pa
    ON l.hadm_id = pa.hadm_id
  WHERE
    LOWER(d.label) = 'creatinine'
    AND l.valuenum IS NOT NULL
    AND l.charttime >= pa.admittime
    AND l.charttime <= DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
),
avg_creatinine_per_admission AS (
  SELECT
    hadm_id,
    AVG(valuenum) AS avg_creatinine_24h
  FROM
    creatinine_labs
  GROUP BY
    hadm_id
)
SELECT
  MIN(avg_creatinine_24h) AS min_24h_avg_creatinine
FROM
  avg_creatinine_per_admission;