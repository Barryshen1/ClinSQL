WITH female_elderly_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 88 AND 98
),

hfnc_stays AS (
  -- Find ICU stays where HFNC was used at any time
  SELECT DISTINCT
    fe.stay_id
  FROM
    female_elderly_icu fe
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON fe.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (226732, 227287)
    AND LOWER(ce.value) LIKE '%high flow nasal cannula%'
),

gcs_on_day2plus AS (
  SELECT
    fe.subject_id,
    fe.hadm_id,
    fe.stay_id,
    ce.charttime,
    ce.valuenum AS gcs_total,
    FLOOR(TIMESTAMP_DIFF(ce.charttime, fe.intime, HOUR)/24) + 1 AS icu_day
  FROM
    female_elderly_icu fe
    JOIN hfnc_stays hs
      ON fe.stay_id = hs.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON fe.stay_id = ce.stay_id
  WHERE
    ce.itemid = 223901 -- GCS Total
    AND ce.valuenum IS NOT NULL
    AND FLOOR(TIMESTAMP_DIFF(ce.charttime, fe.intime, HOUR)/24) + 1 >= 2
)

SELECT
  COUNT(*) AS num_gcs_records,
  APPROX_QUANTILES(gcs_total, 2)[OFFSET(1)] AS median_gcs_total
FROM
  gcs_on_day2plus;