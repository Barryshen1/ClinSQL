WITH acs_admissions AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%acute%'
),
initial_trop AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum,
    le.ref_range_upper,
    le.charttime,
    ROW_NUMBER() OVER (
      PARTITION BY le.subject_id, le.hadm_id
      ORDER BY le.charttime
    ) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` di
      ON le.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
),
elevated_initial_trop AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    initial_trop
  WHERE
    rn = 1
    AND valuenum > ref_range_upper
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN acs_admissions acs
      ON a.subject_id = acs.subject_id
     AND a.hadm_id = acs.hadm_id
    JOIN elevated_initial_trop eit
      ON a.subject_id = eit.subject_id
     AND a.hadm_id = eit.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
)
SELECT
  COUNT(*) AS cohort_size,
  ROUND(
    AVG(
      TIMESTAMP_DIFF(dischtime, admittime, DAY)
    ),
    2
  ) AS avg_length_of_stay_days,
  ROUND(
    100.0 * SUM(hospital_expire_flag) / COUNT(*),
    2
  ) AS in_hospital_mortality_percent
FROM
  cohort;