SELECT
  AVG(ce.valuenum) AS avg_map
FROM
  physionet-data.mimiciv_3_1_icu.icustays AS icu
JOIN
  physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON icu.subject_id = pat.subject_id
JOIN
  physionet-data.mimiciv_3_1_icu.chartevents AS ce
  ON icu.stay_id = ce.stay_id
JOIN
  physionet-data.mimiciv_3_1_icu.d_items AS di
  ON ce.itemid = di.itemid
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 89 AND 99
  AND di.label = 'MAP'
  AND ce.charttime BETWEEN icu.intime AND icu.intime + INTERVAL 24 HOUR
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0;