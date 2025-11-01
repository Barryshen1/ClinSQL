WITH male_icu_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON p.subject_id = icu.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
      AND icu.hadm_id = a.hadm_id
  WHERE
    p.gender = 'M'
    AND a.dischtime IS NOT NULL
),

serum_potassium_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%potassium%'
    AND LOWER(fluid) = 'serum'
),

discharge_day_potassium AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    INNER JOIN male_icu_admissions m
      ON l.subject_id = m.subject_id
      AND l.hadm_id = m.hadm_id
    INNER JOIN serum_potassium_items k
      ON l.itemid = k.itemid
  WHERE
    l.valuenum IS NOT NULL
    AND DATE(l.charttime) = DATE(m.dischtime)
)

SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS potassium_75th_percentile
FROM
  discharge_day_potassium
;