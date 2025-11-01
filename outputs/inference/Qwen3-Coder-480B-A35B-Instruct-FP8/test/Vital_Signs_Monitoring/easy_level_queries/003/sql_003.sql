WITH hr_per_stay AS (
  SELECT
    icu.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON icu.stay_id = ce.stay_id
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 40 AND 50
    AND di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
  GROUP BY
    icu.stay_id
)
SELECT
  APPROX_QUANTILES(mean_hr, 2)[OFFSET(1)] AS median_per_stay_mean_heart_rate
FROM
  hr_per_stay;