SELECT
  APPROX_QUANTILES(i.los, 4)[OFFSET(1)] AS approx_25th_percentile_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
ON
  p.subject_id = d.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu.icustays` AS i
ON
  d.hadm_id = i.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
ON
  d.icd_code = dd.icd_code
  AND d.icd_version = dd.icd_version
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 48 AND 58
  AND (
    (d.icd_version = 9 AND d.icd_code LIKE '584%')
    OR (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
  )
;