WITH first_abg_ph AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.valuenum AS ph_value,
    ce.charttime,
    ROW_NUMBER() OVER (
      PARTITION BY ce.stay_id
      ORDER BY ce.charttime ASC
    ) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND di.unitname = 'pH'
    AND ce.valuenum IS NOT NULL
    -- Restrict to measurements taken within 1 hour of ICU admission
    AND ce.charttime BETWEEN icu.intime AND icu.intime + INTERVAL 1 HOUR
)
SELECT
  -- Approximate median (50th percentile) of the first pH per ICU stay
  APPROX_QUANTILES(ph_value, 2)[OFFSET(1)] AS median_abg_pH
FROM
  first_abg_ph
WHERE
  rn = 1;