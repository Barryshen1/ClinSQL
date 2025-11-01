WITH potassium_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%potassium%'
    AND LOWER(fluid) = 'serum'
),
target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age = 56
),
icu_stays AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN target_patients p ON icu.subject_id = p.subject_id
),
potassium_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN potassium_items k ON l.itemid = k.itemid
  INNER JOIN icu_stays icu
    ON l.subject_id = icu.subject_id
    AND l.hadm_id = icu.hadm_id
    AND l.charttime >= icu.intime
    AND l.charttime < icu.outtime
  WHERE l.valuenum IS NOT NULL
    AND (l.valueuom IS NULL OR LOWER(l.valueuom) = 'meq/l')
)
, peak_potassium_per_stay AS (
  SELECT
    stay_id,
    MAX(valuenum) AS peak_potassium
  FROM potassium_labs
  GROUP BY stay_id
)
SELECT
  STDDEV_SAMP(peak_potassium) AS stddev_peak_potassium_meq_l
FROM peak_potassium_per_stay
;