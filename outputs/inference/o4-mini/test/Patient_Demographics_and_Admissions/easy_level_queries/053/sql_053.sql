WITH aki_cohort AS (
  SELECT
    A.subject_id,
    A.hadm_id,
    A.admittime,
    A.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` A
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` P
      ON A.subject_id = P.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` D
      ON A.hadm_id = D.hadm_id
  WHERE
    P.gender = 'F'
    AND P.anchor_age BETWEEN 52 AND 62
    AND D.icd_version = 9
    AND D.icd_code LIKE '584%'  -- ICD-9 codes for AKI
),
aki_with_readmit AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    -- Look ahead to the next admission for the same patient
    LEAD(admittime) OVER (
      PARTITION BY subject_id
      ORDER BY admittime
    ) AS next_admittime
  FROM
    aki_cohort
),
aki_flagged AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    -- Flag if next admission is within 30 days of discharge
    CASE
      WHEN next_admittime IS NOT NULL
       AND next_admittime <= TIMESTAMP_ADD(dischtime, INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS readmit30
  FROM
    aki_with_readmit
)
SELECT
  STDDEV_SAMP(readmit30) AS stddev_readmission_30d
FROM
  aki_flagged;