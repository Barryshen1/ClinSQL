WITH
-- Get male patients aged 76-86
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 76 AND 86
),

-- Get first admission per patient
first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    subject_id IN (SELECT subject_id FROM eligible_patients)
),
first_admissions_filtered AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime
  FROM
    first_admissions
  WHERE
    admission_rank = 1
),

-- Identify DAPT medications (aspirin + P2Y12 inhibitor)
dapt_medications AS (
  SELECT
    subject_id,
    hadm_id,
    drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%aspirin%'
    OR LOWER(drug) LIKE '%clopidogrel%'
    OR LOWER(drug) LIKE '%ticagrelor%'
    OR LOWER(drug) LIKE '%prasugrel%'
),

-- Patients on DAPT (both aspirin and P2Y12 inhibitor)
dapt_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    first_admissions_filtered a
  JOIN
    dapt_medications d1 ON a.subject_id = d1.subject_id AND a.hadm_id = d1.hadm_id
  JOIN
    dapt_medications d2 ON a.subject_id = d2.subject_id AND a.hadm_id = d2.hadm_id
  WHERE
    LOWER(d1.drug) LIKE '%aspirin%'
    AND (
      LOWER(d2.drug) LIKE '%clopidogrel%'
      OR LOWER(d2.drug) LIKE '%ticagrelor%'
      OR LOWER(d2.drug) LIKE '%prasugrel%'
    )
    AND d1.drug <> d2.drug
),

-- Get ICU stays for DAPT patients
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, DAY) AS icu_los_days
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    dapt_patients d ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
)

-- Calculate average ICU LOS
SELECT
  AVG(icu_los_days) AS avg_icu_los_days
FROM
  icu_stays;