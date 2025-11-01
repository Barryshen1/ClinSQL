SELECT
  MAX(rr_measurements.valuenum) AS max_respiratory_rate
FROM (
  SELECT
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS iu
    ON ce.subject_id = iu.subject_id
   AND ce.hadm_id = iu.hadm_id
   AND ce.stay_id = iu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ce.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%respiratory rate%'
    AND ce.charttime >= iu.intime
    AND ce.charttime <= TIMESTAMP_ADD(iu.intime, INTERVAL 24 HOUR)
    AND p.gender = 'Female'
    AND p.anchor_age BETWEEN 38 AND 48
    AND ce.valuenum IS NOT NULL
) AS rr_measurements;