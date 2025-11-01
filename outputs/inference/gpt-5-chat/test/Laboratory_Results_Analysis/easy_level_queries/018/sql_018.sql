WITH ph_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%ph%' 
    AND LOWER(label) LIKE '%arterial%'
),
ph_first6h AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum AS ph_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN ph_items pi
    ON ce.itemid = pi.itemid
  WHERE ce.valuenum IS NOT NULL
)
, female_icustays AS (
  SELECT icu.stay_id, icu.subject_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
)
, ph_on_admit AS (
  SELECT
    f.stay_id,
    ph.ph_value
  FROM female_icustays f
  JOIN ph_first6h ph
    ON f.stay_id = ph.stay_id
   AND ph.charttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 6 HOUR)
   AND ph.ph_value BETWEEN 6.5 AND 8.0 -- optional physiologic range filter
)
SELECT
  APPROX_QUANTILES(ph_value, 100)[OFFSET(50)] AS median_ph_on_icu_admit_female
FROM ph_on_admit;