WITH hr_items AS (
  -- identify heart-rate related itemids
  SELECT DISTINCT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
     OR LOWER(label) LIKE '%pulse%'
     OR LOWER(abbreviation) LIKE '%hr%'
),

first_hr_per_stay AS (
  -- first heart-rate measurement on or after ICU admission for each stay
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    ce.valueuom,
    icu.intime,
    ROW_NUMBER() OVER (PARTITION BY ce.stay_id ORDER BY ce.charttime, ce.storetime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN hr_items hi
    ON ce.itemid = hi.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  WHERE ce.valuenum IS NOT NULL
    -- consider measurements at or after ICU admission and within the ICU stay
    AND ce.charttime >= icu.intime
    AND ce.charttime <= icu.outtime
)

SELECT
  MIN(f.valuenum) AS min_first_recorded_hr_bpm
FROM first_hr_per_stay f
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON f.subject_id = p.subject_id
WHERE f.rn = 1
  AND p.gender = 'F'
  AND p.anchor_age BETWEEN 38 AND 48;