WITH female_icu_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    USING(subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 39 AND 49
),
rr_per_stay AS (
  SELECT
    f.stay_id,
    AVG(ce.valuenum) AS mean_rr
  FROM female_icu_stays f
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = f.subject_id
   AND ce.hadm_id    = f.hadm_id
   AND ce.stay_id    = f.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    USING(itemid)
  WHERE LOWER(di.label) LIKE '%respiratory rate%'
    AND ce.valuenum IS NOT NULL
  GROUP BY f.stay_id
)
SELECT
  quartiles[OFFSET(3)] AS rr_75th_percentile
FROM (
  SELECT
    APPROX_QUANTILES(mean_rr, 4) AS quartiles
  FROM rr_per_stay
);