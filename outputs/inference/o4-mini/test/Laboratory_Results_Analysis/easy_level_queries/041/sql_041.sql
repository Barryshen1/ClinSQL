WITH pneumonia_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON a.subject_id = di.subject_id
     AND a.hadm_id    = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code    = dd.icd_code
     AND di.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
  GROUP BY
    a.subject_id,
    a.hadm_id,
    a.admittime
),

creatinine_measurements AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    le.valuenum AS creat_val
  FROM
    pneumonia_admissions pa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON pa.subject_id = le.subject_id
     AND pa.hadm_id    = le.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON le.itemid = li.itemid
  WHERE
    LOWER(li.label) LIKE '%creatinine%'
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN pa.admittime AND TIMESTAMP_ADD(pa.admittime, INTERVAL 24 HOUR)
),

avg_creatinine_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    AVG(creat_val) AS avg_creat
  FROM
    creatinine_measurements
  GROUP BY
    subject_id,
    hadm_id
)

SELECT
  STDDEV_SAMP(avg_creat) AS sd_of_avg_creatinine_first_24h
FROM
  avg_creatinine_per_admission;