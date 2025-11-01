SELECT
  STDDEV_SAMP(ce.valuenum) AS sbp_sd
FROM
  physionet-data.mimiciv_3_1_icu.chartevents ce
JOIN
  physionet-data.mimiciv_3_1_icu.icustays icu
    ON ce.subject_id = icu.subject_id
    AND ce.hadm_id = icu.hadm_id
    AND ce.stay_id = icu.stay_id
JOIN
  physionet-data.mimiciv_3_1_hosp.patients p
    ON ce.subject_id = p.subject_id
JOIN
  physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
WHERE
  p.gender = 'M'
  AND p.anchor_age BETWEEN 76 AND 86
  AND icu.first_careunit IN ('IMC', 'STEPDOWN')
  AND di.label LIKE '%Systolic Blood Pressure%'
  AND ce.valuenum IS NOT NULL
  AND ce.valuenum > 0
  AND ce.charttime BETWEEN icu.intime AND DATETIME_ADD(icu.intime, INTERVAL 24 HOUR);