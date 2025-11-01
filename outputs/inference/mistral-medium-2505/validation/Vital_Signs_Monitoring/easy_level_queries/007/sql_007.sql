WITH female_patients_73_83 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    EXTRACT(YEAR FROM a.admittime) AS admission_year,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 73 AND 83
),

first_respiratory_rate AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.age_at_admission,
    ce.valuenum AS respiratory_rate,
    ROW_NUMBER() OVER (PARTITION BY f.hadm_id ORDER BY ce.charttime) AS rn
  FROM
    female_patients_73_83 f
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON
    f.hadm_id = icu.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    icu.stay_id = ce.stay_id
    AND ce.itemid = 220210  -- Respiratory Rate
  WHERE
    ce.valuenum IS NOT NULL
)

SELECT
  STDDEV(respiratory_rate) AS sd_first_respiratory_rate
FROM
  first_respiratory_rate
WHERE
  rn = 1  -- Only the first respiratory rate per admission
;