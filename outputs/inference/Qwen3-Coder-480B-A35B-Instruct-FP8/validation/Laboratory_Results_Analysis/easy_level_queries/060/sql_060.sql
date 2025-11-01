WITH pneumonia_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
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
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age + DATE_DIFF(a.admittime, DATETIME(p.anchor_year, 1, 1, 0, 0, 0), YEAR) = 67
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
    AND d.seq_num = 1
),
glucose_labs AS (
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
    LOWER(d.label) = 'glucose'
    AND LOWER(d.fluid) = 'blood'
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0
    AND l.charttime >= pa.admittime
    AND l.charttime <= DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
),
mean_glucose_per_admission AS (
  SELECT
    hadm_id,
    AVG(valuenum) AS mean_glucose
  FROM
    glucose_labs
  GROUP BY
    hadm_id
)
SELECT
  APPROX_QUANTILES(mean_glucose, 100)[OFFSET(75)] AS percentile_75_mean_glucose
FROM
  mean_glucose_per_admission
WHERE
  mean_glucose IS NOT NULL;