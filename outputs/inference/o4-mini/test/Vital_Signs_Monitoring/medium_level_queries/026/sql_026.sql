WITH rr_item AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    label = 'Respiratory Rate'
),

eligible_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
),

stay_rr AS (
  SELECT
    es.stay_id,
    AVG(ce.valuenum) AS avg_rr
  FROM
    eligible_stays es
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    es.subject_id = ce.subject_id
    AND es.hadm_id   = ce.hadm_id
    AND es.stay_id   = ce.stay_id
  JOIN
    rr_item rri
  ON
    ce.itemid = rri.itemid
  WHERE
    ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN es.intime
                        AND TIMESTAMP_ADD(es.intime, INTERVAL 48 HOUR)
  GROUP BY
    es.stay_id
)

SELECT
  100.0 * COUNTIF(avg_rr <= 12) / COUNT(*) AS percentile_of_12_breaths_per_min
FROM
  stay_rr;