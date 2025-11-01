SELECT
  MAX(ce.valuenum) AS max_respiratory_rate
FROM
  `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN
  `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON p.subject_id = a.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu`.icustays icu
  ON p.subject_id = icu.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu`.chartevents ce
  ON icu.stay_id = ce.stay_id
JOIN
  `physionet-data.mimiciv_3_1_icu`.d_items di
  ON ce.itemid = di.itemid
WHERE
  p.gender = 'M'
  AND di.label = 'Respiratory Rate'
  AND di.linksto = 'chartevents'
  AND ce.charttime >= DATETIME_ADD(icu.intime, INTERVAL 2 DAY)
  AND ce.valuenum IS NOT NULL
  AND (
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)
  ) BETWEEN 52 AND 62;