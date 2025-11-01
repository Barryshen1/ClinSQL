SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS percentile_75
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON p.subject_id = ce.subject_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND ce.itemid IN (220050, 220179)
  AND ce.valuenum IS NOT NULL;