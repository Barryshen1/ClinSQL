WITH female_stays AS (
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` cs
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
),
temps AS (
  SELECT
    fs.stay_id,
    ce.valuenum
  FROM
    female_stays fs
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON fs.subject_id = ce.subject_id
     AND fs.hadm_id    = ce.hadm_id
     AND fs.stay_id    = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    LOWER(di.label) LIKE '%temp%'
    AND ce.valuenum IS NOT NULL
),
stay_means AS (
  SELECT
    stay_id,
    AVG(valuenum) AS mean_temp
  FROM
    temps
  GROUP BY
    stay_id
)
SELECT
  approx_quantiles(mean_temp, 100)[OFFSET(75)] AS p75_mean_temp
FROM
  stay_means;