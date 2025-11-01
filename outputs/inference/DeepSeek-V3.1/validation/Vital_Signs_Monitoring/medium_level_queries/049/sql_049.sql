WITH cohort_avg_sbp AS (
  SELECT 
    ie.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
      AND ie.subject_id = ce.subject_id
      AND ie.hadm_id = ce.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND ce.itemid IN (220179, 220050)  -- Systolic BP
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime
    AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
  GROUP BY ie.stay_id
)
SELECT 
  COUNTIF(avg_sbp <= 130) * 100.0 / COUNT(*) AS percentile
FROM cohort_avg_sbp;