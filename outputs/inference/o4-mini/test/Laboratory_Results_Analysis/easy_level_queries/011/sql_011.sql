SELECT
  STDDEV_POP(peak_potassium) AS stddev_peak_potassium_mEq_per_L
FROM (
  -- Compute peak potassium per ICU stay
  SELECT
    icu.stay_id,
    MAX(ce.valuenum) AS peak_potassium
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON a.subject_id = icu.subject_id
      AND a.hadm_id = icu.hadm_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON ce.subject_id = icu.subject_id
      AND ce.hadm_id    = icu.hadm_id
      AND ce.stay_id    = icu.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 56
    -- Serum potassium entries
    AND LOWER(di.label) LIKE '%potassium%'
    AND di.unitname = 'mEq/L'
    -- Only charted during this ICU stay
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
    AND ce.valuenum IS NOT NULL
  GROUP BY
    icu.stay_id
);