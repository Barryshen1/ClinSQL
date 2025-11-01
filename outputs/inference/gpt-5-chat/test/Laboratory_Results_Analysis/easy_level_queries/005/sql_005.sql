WITH sodium_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%sodium%'
    AND LOWER(fluid) = 'blood'
),
male_89_icu_admissions AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age = 89
),
first_sodium_per_hadm AS (
  SELECT
    la.hadm_id,
    la.valuenum,
    la.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` la
  JOIN sodium_itemids si
    ON la.itemid = si.itemid
  JOIN male_89_icu_admissions m
    ON la.hadm_id = m.hadm_id
  WHERE la.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY la.hadm_id ORDER BY la.charttime) = 1
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3
FROM first_sodium_per_hadm;