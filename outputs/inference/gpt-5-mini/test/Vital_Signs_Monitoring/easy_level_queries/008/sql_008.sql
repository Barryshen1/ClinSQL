WITH rr_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    ce.valueuom,
    di.label AS item_label,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE ce.valuenum IS NOT NULL
    -- ensure the charttime is during the ICU stay and on ICU day 2 or later
    AND ce.charttime >= icu.intime
    AND TIMESTAMP_DIFF(ce.charttime, icu.intime, DAY) >= 1
    -- cohort: males aged 52-62 (inclusive)
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    -- identify respiratory rate itemids by label/abbreviation heuristics
    AND (
      LOWER(COALESCE(di.label, '')) LIKE '%respir%'
      OR LOWER(COALESCE(di.label, '')) LIKE '%resp rate%'
      OR LOWER(COALESCE(di.abbreviation, '')) LIKE '%rr%'
    )
)

SELECT
  MAX(valuenum) AS max_respiratory_rate,
  -- optional: unit (may vary across itemids)
  ANY_VALUE(valueuom) AS example_unit
FROM rr_events;