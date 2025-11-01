WITH cabg_patients AS (
  -- Get patients who are males aged 74-84 and had a CABG procedure
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON a.hadm_id = proc.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND proc.icd_code LIKE '021%' OR proc.icd_code LIKE '022%'  -- CABG ICD-10-PCS codes
),

first_cabg_admissions AS (
  -- Filter to only the first CABG admission per patient
  SELECT
    subject_id,
    hadm_id,
    admittime,
    anchor_age,
    gender
  FROM
    cabg_patients
  WHERE
    admission_rank = 1
),

icu_los AS (
  -- Calculate ICU LOS for these admissions
  SELECT
    f.subject_id,
    f.hadm_id,
    f.admittime,
    f.anchor_age,
    f.gender,
    i.stay_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, HOUR) / 24.0 AS icu_los_days
  FROM
    first_cabg_admissions f
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON f.hadm_id = i.hadm_id
  WHERE
    i.outtime > i.intime  -- Ensure valid ICU stay
)

-- Calculate mean ICU LOS
SELECT
  AVG(icu_los_days) AS mean_icu_los_days
FROM
  icu_los;