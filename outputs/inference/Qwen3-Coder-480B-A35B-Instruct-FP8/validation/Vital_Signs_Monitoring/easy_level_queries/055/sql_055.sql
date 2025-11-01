SELECT
  STDDEV_SAMP(ce.valuenum) AS sbp_stddev
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` AS icu
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON icu.subject_id = pat.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  ON icu.stay_id = ce.stay_id
JOIN
  `physionet-data.mimiciv_3_1_icu.d_items` AS di
  ON ce.itemid = di.itemid
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 76 AND 86
  AND LOWER(icu.first_careunit) IN ('stepdown', 'imc', 'intermediate')
  AND LOWER(di.label) LIKE '%systolic%'
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0
  AND ce.charttime >= icu.intime
  AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR);