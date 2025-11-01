WITH relevant_patients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F' AND p.anchor_age = 64
),
ed_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.admission_location = 'EMERGENCY ROOM'
    AND a.subject_id IN (SELECT subject_id FROM relevant_patients)
),
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  WHERE
    i.subject_id IN (SELECT subject_id FROM ed_admissions)
),
systolic_bp AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.valuenum AS systolic_bp -- Use valuenum for numeric calculations
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` AS d
    ON c.itemid = d.itemid
  WHERE
    d.label = 'Systolic blood pressure'
    AND c.stay_id IN (SELECT stay_id FROM icu_stays)
),
max_systolic_bp AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    MAX(systolic_bp) AS max_systolic_bp
  FROM
    systolic_bp
  GROUP BY
    subject_id,
    hadm_id,
    stay_id
)
SELECT
  PERCENTILE_CONT(0.75, max_systolic_bp)
FROM
  max_systolic_bp;