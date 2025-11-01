WITH first_rr AS (
  SELECT
    p.subject_id,
    icu.stay_id,
    ce.valuenum AS rr_value,
    ROW_NUMBER() OVER (
      PARTITION BY p.subject_id, icu.stay_id
      ORDER BY ce.charttime
    ) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON p.subject_id = icu.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON icu.subject_id = ce.subject_id
      AND icu.hadm_id    = ce.hadm_id
      AND icu.stay_id    = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
      ON ce.itemid = di.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND LOWER(di.label) LIKE '%respiratory rate%'
    AND ce.valuenum IS NOT NULL
)
SELECT
  STDDEV_SAMP(rr_value) AS sd_first_respiratory_rate
FROM
  first_rr
WHERE
  rn = 1;