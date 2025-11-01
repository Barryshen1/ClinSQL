WITH female_icustays AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icustays
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icustays.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
),

hr_first24 AS (
  SELECT
    f.stay_id,
    AVG(ce.valuenum) AS avg_hr
  FROM
    female_icustays f
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
      ON f.subject_id = ce.subject_id
     AND f.hadm_id    = ce.hadm_id
     AND f.stay_id    = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
      ON ce.itemid = di.itemid
  WHERE
    di.label = 'Heart Rate'
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN f.intime
                        AND TIMESTAMP_ADD(f.intime, INTERVAL 24 HOUR)
  GROUP BY
    f.stay_id
)

SELECT
  ROUND(
    100.0 * COUNTIF(avg_hr <= 110) / COUNT(*),
    2
  ) AS percentile_rank_of_110
FROM
  hr_first24;