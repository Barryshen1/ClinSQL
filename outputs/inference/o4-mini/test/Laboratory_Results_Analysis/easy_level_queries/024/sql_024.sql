WITH sepsis_admissions AS (
  -- Identify admissions with at least one sepsis diagnosis
  SELECT DISTINCT
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%sepsis%'
),
male_sepsis_admissions AS (
  -- Filter to male patients in those admissions
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN sepsis_admissions s
      ON a.hadm_id = s.hadm_id
  WHERE
    p.gender = 'M'
),
first_platelet_per_admission AS (
  -- For each admission, find the first platelet lab within 24h
  SELECT
    m.hadm_id,
    MIN(le.charttime) AS first_charttime
  FROM
    male_sepsis_admissions m
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON m.hadm_id = le.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON le.itemid = li.itemid
  WHERE
    -- platelet‐related lab items
    LOWER(li.label) LIKE '%platelet%'
    -- within 24 hours of admission
    AND le.charttime BETWEEN m.admittime
                         AND TIMESTAMP_ADD(m.admittime, INTERVAL 24 HOUR)
    -- numeric value present
    AND le.valuenum IS NOT NULL
  GROUP BY
    m.hadm_id
),
platelet_values AS (
  -- Retrieve the corresponding valuenum for those first measurements
  SELECT
    f.hadm_id,
    le.valuenum AS platelet_count
  FROM
    first_platelet_per_admission f
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON f.hadm_id = le.hadm_id
     AND f.first_charttime = le.charttime
     AND le.valuenum IS NOT NULL
)
-- Compute the sample standard deviation of admission platelet counts
SELECT
  STDDEV_SAMP(platelet_count) AS sd_platelet_count
FROM
  platelet_values;