WITH PatientCohort AS (
  -- Step 1: Select male patients within the 77-87 age range at the time of admission.
  SELECT
    adm.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  WHERE
    p.gender = 'M'
    -- Calculate age at the time of hospital admission
    AND (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year + p.anchor_age) BETWEEN 77 AND 87
),

FirstGCSEvents AS (
  -- Step 2: For each ICU stay in the patient cohort, find the first recorded GCS Total score.
  SELECT
    ce.valuenum,
    -- Rank GCS measurements by time for each ICU stay to find the earliest one.
    ROW_NUMBER() OVER(PARTITION BY ce.stay_id ORDER BY ce.charttime ASC) AS rn
  FROM
    PatientCohort AS pc
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON pc.hadm_id = icu.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON icu.stay_id = ce.stay_id
  WHERE
    -- itemid 226758 corresponds to 'GCS Total'
    ce.itemid = 226758
    AND ce.valuenum IS NOT NULL
)

-- Step 3: Calculate the average of these first GCS scores.
SELECT
  AVG(fg.valuenum) AS avg_first_gcs_total
FROM
  FirstGCSEvents AS fg
WHERE
  fg.rn = 1;