WITH eligible_stays AS (
  SELECT
    icustays.stay_id,
    patients.anchor_age,
    EXTRACT(YEAR FROM icustays.intime) AS intime_year,
    patients.anchor_year,
    patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year) AS age_during_stay
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE patients.gender = 'M'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) BETWEEN 48 AND 58
)
SELECT AVG(max_map) AS avg_max_map
FROM (
  SELECT
    es.stay_id,
    MAX(ce.valuenum) AS max_map
  FROM eligible_stays es
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON es.stay_id = ce.stay_id
  WHERE ce.itemid = 52
  GROUP BY es.stay_id
) AS max_maps_per_stay;