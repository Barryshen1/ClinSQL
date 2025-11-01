SELECT
  STDDEV_SAMP(ce.valuenum) AS sd_sbp_first_24h
FROM
  `physionet-data.mimiciv_3_1_icu.icustays` AS s
JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON s.subject_id = a.subject_id
   AND s.hadm_id    = a.hadm_id
JOIN
  `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON s.subject_id = p.subject_id
JOIN
  `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON s.subject_id = ce.subject_id
   AND s.hadm_id    = ce.hadm_id
   AND s.stay_id    = ce.stay_id
JOIN
  `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
WHERE
  -- Only males aged 76–86
  p.gender = 'M'
  AND p.anchor_age BETWEEN 76 AND 86
  -- Step-down / IMC units
  AND UPPER(s.first_careunit) LIKE '%STEP%'
  -- Only SBP measurements
  AND ce.valuenum IS NOT NULL
  AND (
    LOWER(di.label) LIKE '%systolic%'
    OR LOWER(di.label) LIKE '%sys bp%'
  )
  -- Measurements in first 24h of ICU stay
  AND ce.charttime BETWEEN s.intime
                      AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR);