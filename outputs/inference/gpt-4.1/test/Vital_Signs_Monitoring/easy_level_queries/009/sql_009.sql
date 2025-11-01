WITH temp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE 
    LOWER(label) LIKE '%temp%' 
    AND (LOWER(unitname) = '°f' OR LOWER(label) LIKE '%fahrenheit%')
),
female_aged_86_96_icustays AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 86 AND 96
),
temps_in_first_24hr AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN female_aged_86_96_icustays icu
    ON ce.subject_id = icu.subject_id
    AND ce.hadm_id = icu.hadm_id
    AND ce.stay_id = icu.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM temp_itemids)
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
)
SELECT
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS temp_75th_percentile_F
FROM temps_in_first_24hr
;