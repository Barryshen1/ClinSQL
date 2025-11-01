WITH first_spo2 AS (
  SELECT
    ce.subject_id,
    ce.valuenum AS spo2
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` s
    USING (subject_id)
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    USING (subject_id, hadm_id, stay_id)
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND ce.valuenum IS NOT NULL
    AND LOWER(di.label) LIKE '%spo2%'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ce.subject_id ORDER BY ce.charttime) = 1
)
SELECT
  quartiles[OFFSET(1)] AS spo2_q1,
  quartiles[OFFSET(3)] AS spo2_q3
FROM (
  SELECT
    APPROX_QUANTILES(spo2, 4) AS quartiles
  FROM
    first_spo2
);