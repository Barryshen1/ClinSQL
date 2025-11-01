WITH stepdown_cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    icu.hadm_id,
    icu.stay_id,
    icu.first_careunit,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND LOWER(icu.first_careunit) LIKE '%stepdown%'
),
sbp_events AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  INNER JOIN stepdown_cohort AS coh
    ON c.stay_id = coh.stay_id
  WHERE c.itemid IN (220050, 220179) -- SBP non-invasive / invasive
    AND c.valuenum IS NOT NULL
    AND c.charttime BETWEEN coh.intime AND TIMESTAMP_ADD(coh.intime, INTERVAL 24 HOUR)
)
SELECT
  coh.subject_id,
  coh.hadm_id,
  coh.stay_id,
  coh.anchor_age,
  coh.gender,
  coh.first_careunit,
  STDDEV_SAMP(sbp.valuenum) AS sbp_sd_24h
FROM stepdown_cohort AS coh
LEFT JOIN sbp_events AS sbp
  ON coh.stay_id = sbp.stay_id
GROUP BY coh.subject_id, coh.hadm_id, coh.stay_id, coh.anchor_age, coh.gender, coh.first_careunit
ORDER BY coh.anchor_age, coh.subject_id;