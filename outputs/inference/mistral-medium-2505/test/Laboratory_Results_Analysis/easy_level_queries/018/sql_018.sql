WITH female_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
),

icu_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE
    subject_id IN (SELECT subject_id FROM female_patients)
),

ph_itemid AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    label = 'pH'
    AND category = 'Labs'
),

first_ph_on_admission AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS ph_value,
    ROW_NUMBER() OVER (PARTITION BY ce.subject_id, ce.hadm_id, ce.stay_id ORDER BY ce.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    icu_admissions ia ON ce.subject_id = ia.subject_id AND ce.hadm_id = ia.hadm_id AND ce.stay_id = ia.stay_id
  JOIN
    ph_itemid pi ON ce.itemid = pi.itemid
  WHERE
    ce.charttime >= ia.intime
    AND ce.valuenum IS NOT NULL
)

SELECT
  PERCENTILE_CONT(ph_value, 0.5) OVER() AS median_ph_on_icu_admission
FROM
  first_ph_on_admission
WHERE
  rn = 1
LIMIT 1;