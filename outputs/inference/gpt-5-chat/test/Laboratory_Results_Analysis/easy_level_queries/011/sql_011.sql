WITH potassium_labs AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON icu.subject_id = le.subject_id
   AND icu.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE pat.anchor_age = 56
    AND pat.gender = 'M'
    AND LOWER(dli.label) LIKE '%potassium%'
    AND LOWER(dli.fluid) = 'blood'
    AND LOWER(le.valueuom) = 'meq/l'
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN icu.intime AND icu.outtime
),
peak_per_stay AS (
  SELECT
    stay_id,
    MAX(valuenum) AS peak_potassium
  FROM potassium_labs
  GROUP BY stay_id
)
SELECT
  STDDEV(peak_potassium) AS stddev_peak_potassium_meql
FROM peak_per_stay;