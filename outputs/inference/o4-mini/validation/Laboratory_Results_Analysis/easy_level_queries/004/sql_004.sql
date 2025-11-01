WITH sepsis_admissions AS (
  SELECT DISTINCT
    ad.subject_id,
    ad.hadm_id,
    ad.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` ad
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
      ON ad.subject_id = pt.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON ad.subject_id = di.subject_id
      AND ad.hadm_id    = di.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON di.icd_code    = dd.icd_code
      AND di.icd_version = dd.icd_version
  WHERE
    pt.gender = 'F'
    AND pt.anchor_age = 76
    AND LOWER(dd.long_title) LIKE '%sepsis%'
),
platelet_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE
    LOWER(label) LIKE '%platelet%'
),
per_admission_avg AS (
  SELECT
    sa.hadm_id,
    AVG(le.valuenum) AS avg_platelet
  FROM
    sepsis_admissions sa
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON sa.subject_id = le.subject_id
      AND sa.hadm_id    = le.hadm_id
    JOIN platelet_items pi
      ON le.itemid = pi.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime BETWEEN sa.admittime
                         AND TIMESTAMP_ADD(sa.admittime, INTERVAL 24 HOUR)
  GROUP BY
    sa.hadm_id
)
SELECT
  -- Extract the 50th percentile (median) from 100 quantiles
  APPROX_QUANTILES(avg_platelet, 100)[OFFSET(50)] AS median_platelet
FROM
  per_admission_avg;