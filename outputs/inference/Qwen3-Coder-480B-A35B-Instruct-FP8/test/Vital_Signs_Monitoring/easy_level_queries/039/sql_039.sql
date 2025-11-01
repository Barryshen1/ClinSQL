WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
),

icu_admissions AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN filtered_patients fp ON fp.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON adm.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat ON pat.subject_id = icu.subject_id
  WHERE
    EXTRACT(YEAR FROM icu.intime) - pat.anchor_year + pat.anchor_age BETWEEN 51 AND 61
),

first_rr AS (
  SELECT
    ce.stay_id,
    MIN(ce.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON di.itemid = ce.itemid
  WHERE
    LOWER(di.label) LIKE '%respiratory rate%'
    AND ce.charttime IS NOT NULL
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),

rr_values AS (
  SELECT
    ce.stay_id,
    ce.valuenum AS respiratory_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN first_rr fr ON fr.stay_id = ce.stay_id AND fr.first_charttime = ce.charttime
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON di.itemid = ce.itemid
  WHERE
    LOWER(di.label) LIKE '%respiratory rate%'
    AND ce.valuenum IS NOT NULL
)

SELECT
  PERCENTILE_CONT(respiratory_rate, 0.25) OVER() AS rr_25th_percentile
FROM rr_values
LIMIT 1;