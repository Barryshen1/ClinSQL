SELECT
  APPROX_QUANTILES(l.valuenum, 1000)[OFFSET(750)] AS potassium_75th_percentile
FROM
  `physionet-data.mimiciv_3_1_hosp`.patients p
INNER JOIN
  `physionet-data.mimiciv_3_1_icu`.icustays icu
  ON p.subject_id = icu.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON p.subject_id = a.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp`.labevents l
  ON a.hadm_id = l.hadm_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp`.d_labitems d
  ON l.itemid = d.itemid
WHERE
  p.gender = 'M'
  AND LOWER(d.label) = 'potassium'
  AND LOWER(d.fluid) = 'blood'
  AND DATE(l.charttime) = DATE(a.dischtime)
  AND l.valuenum IS NOT NULL;