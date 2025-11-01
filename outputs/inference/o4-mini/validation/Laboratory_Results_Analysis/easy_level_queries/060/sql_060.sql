WITH pneumonia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.subject_id = d.subject_id
     AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
      ON d.icd_code = dicd.icd_code
     AND d.icd_version = dicd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 67
    AND LOWER(dicd.long_title) LIKE '%pneumonia%'
),
mean_glucose_per_admission AS (
  SELECT
    pa.hadm_id,
    AVG(le.valuenum) AS mean_glucose
  FROM
    pneumonia_admissions pa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON pa.subject_id = le.subject_id
     AND pa.hadm_id = le.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
      ON le.itemid = di.itemid
  WHERE
    le.charttime BETWEEN pa.admittime AND TIMESTAMP_ADD(pa.admittime, INTERVAL 1 DAY)
    AND LOWER(di.label) LIKE '%glucose%'
    AND LOWER(di.fluid) LIKE '%blood%'
    AND le.valuenum IS NOT NULL
  GROUP BY
    pa.hadm_id
)
SELECT
  APPROX_QUANTILES(mean_glucose, 100)[OFFSET(75)] AS glucose_75th_percentile
FROM
  mean_glucose_per_admission;