WITH gcs_first AS (
  SELECT
    ce.stay_id,
    MIN(ce.charttime) AS first_charttime
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    di.label = 'GCS Total'
  GROUP BY
    ce.stay_id
)

SELECT
  AVG(ce.valuenum) AS avg_first_gcs
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON p.subject_id = icu.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON icu.stay_id = ce.stay_id
JOIN
  gcs_first g
  ON ce.stay_id = g.stay_id AND ce.charttime = g.first_charttime
JOIN
  `physionet-data.mimiciv_3_1_icu.d_items` di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 77 AND 87
  AND di.label = 'GCS Total'
  AND ce.valuenum IS NOT NULL;