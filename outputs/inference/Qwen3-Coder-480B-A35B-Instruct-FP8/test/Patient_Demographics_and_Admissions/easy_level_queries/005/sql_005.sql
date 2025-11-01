WITH first_icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los,
    i.intime,
    i.outtime,
    ROW_NUMBER() OVER (PARTITION BY i.subject_id ORDER BY i.intime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
),
first_icu_stays_filtered AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    los
  FROM
    first_icu_stays
  WHERE
    rn = 1
),
female_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 77 AND 87
),
dialysis_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%dialysis%'
),
dialysis_patients AS (
  SELECT DISTINCT
    f.subject_id
  FROM
    first_icu_stays_filtered f
  JOIN
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON f.stay_id = pe.stay_id
  JOIN
    dialysis_items di
    ON pe.itemid = di.itemid
)
SELECT
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] - APPROX_QUANTILES(los, 4)[OFFSET(1)] AS iqr
FROM
  first_icu_stays_filtered f
JOIN
  female_patients p
  ON f.subject_id = p.subject_id
JOIN
  dialysis_patients dp
  ON f.subject_id = dp.subject_id;