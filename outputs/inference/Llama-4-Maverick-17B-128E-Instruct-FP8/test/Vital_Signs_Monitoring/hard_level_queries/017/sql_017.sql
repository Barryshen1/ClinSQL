WITH asthma_cohort AS (
  SELECT DISTINCT p.subject_id, ie.stay_id, ie.los, ie.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ie.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 83 AND 93
  AND dicd.long_title LIKE '%Asthma%'
),
asthma_hr AS (
  SELECT ac.stay_id, ce.valuenum AS hr
  FROM asthma_cohort ac
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON ac.stay_id = ce.stay_id
  WHERE ce.itemid = 220050  -- Heart Rate
  AND ce.charttime BETWEEN ac.intime
                      AND DATETIME_ADD(ac.intime, INTERVAL 72 HOUR)
),
instability_score AS (
  SELECT stay_id, STDDEV(hr) AS hr_stddev
  FROM asthma_hr
  GROUP BY stay_id
),
percentiles AS (
  SELECT 
    APPROX_QUANTILES(hr_stddev, 100) AS quantiles
  FROM instability_score
),
matched_cohort AS (
  SELECT DISTINCT p.subject_id, ie.stay_id, ie.los, ie.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie ON p.subject_id = ie.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON ie.hadm_id = di.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version AND dicd.long_title LIKE '%Asthma%'
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 83 AND 93
  AND dicd.icd_code IS NULL  -- No asthma diagnosis
),
matched_hr AS (
  SELECT mc.stay_id, ce.valuenum AS hr
  FROM matched_cohort mc
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON mc.stay_id = ce.stay_id
  WHERE ce.itemid = 220050  -- Heart Rate
  AND ce.charttime BETWEEN mc.intime
                      AND DATETIME_ADD(mc.intime, INTERVAL 72 HOUR)
),
matched_instability_score AS (
  SELECT stay_id, STDDEV(hr) AS hr_stddev
  FROM matched_hr
  GROUP BY stay_id
)

SELECT 
  (SELECT quantiles[OFFSET(25)] FROM percentiles) AS `25th_percentile`,
  (SELECT quantiles[OFFSET(50)] FROM percentiles) AS `50th_percentile`,
  (SELECT quantiles[OFFSET(75)] FROM percentiles) AS `75th_percentile`,
  (SELECT quantiles[OFFSET(95)] FROM percentiles) AS `95th_percentile`,
  (SELECT STDDEV(hr_stddev) FROM instability_score) AS `stddev`,
  (SELECT AVG(los) FROM asthma_cohort) AS avg_icu_los_asthma,
  (SELECT AVG(los) FROM matched_cohort) AS avg_icu_los_matched
FROM (SELECT 1) AS dummy;