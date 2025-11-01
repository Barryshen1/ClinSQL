WITH eligible_patients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),

first_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM (
    SELECT
      subject_id,
      MIN(admittime) AS first_admittime
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions`
    GROUP BY
      subject_id
  ) fa
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON fa.subject_id = a.subject_id
    AND fa.first_admittime = a.admittime
),

anticoagulant_rx AS (
  SELECT DISTINCT
    pr.subject_id,
    pr.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE
    LOWER(pr.drug) LIKE '%warfarin%'
    OR LOWER(pr.drug) LIKE '%heparin%'
    OR LOWER(pr.drug) LIKE '%enoxaparin%'
    OR LOWER(pr.drug) LIKE '%apixaban%'
    OR LOWER(pr.drug) LIKE '%rivaroxaban%'
    OR LOWER(pr.drug) LIKE '%dabigatran%'
    OR LOWER(pr.drug) LIKE '%fondaparinux%'
    OR LOWER(pr.drug) LIKE '%dalteparin%'
    OR LOWER(pr.drug) LIKE '%tinzaparin%'
    OR LOWER(pr.drug) LIKE '%argatroban%'
    OR LOWER(pr.drug) LIKE '%bivalirudin%'
),

cohort AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.admittime,
    fa.dischtime,
    TIMESTAMP_DIFF(fa.dischtime, fa.admittime, DAY) AS los_days
  FROM
    first_admissions fa
    JOIN eligible_patients ep ON fa.subject_id = ep.subject_id
    JOIN anticoagulant_rx arx ON fa.subject_id = arx.subject_id AND fa.hadm_id = arx.hadm_id
  WHERE
    fa.admittime IS NOT NULL
    AND fa.dischtime IS NOT NULL
)

SELECT
  STDDEV_SAMP(los_days) AS sd_los_days
FROM
  cohort
;