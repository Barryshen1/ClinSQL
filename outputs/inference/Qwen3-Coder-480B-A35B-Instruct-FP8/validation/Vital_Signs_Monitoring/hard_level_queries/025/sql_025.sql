WITH vitals AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN (
    'heart rate',
    'systolic blood pressure',
    'diastolic blood pressure',
    'respiratory rate',
    'temperature fahrenheit',
    'o2 saturation pulseoxymetry'
  )
),

admission_diagnosis AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%cardiac arrest%'
),

eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, icu.stay_id, icu.intime, icu.outtime, icu.los, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON p.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN admission_diagnosis ad
    ON adm.hadm_id = ad.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),

vital_scores AS (
  SELECT
    ep.stay_id,
    SUM(
      CASE
        WHEN v.label = 'Heart Rate' AND (ce.valuenum < 50 OR ce.valuenum > 130) THEN 1
        WHEN v.label = 'Systolic blood pressure' AND (ce.valuenum < 90 OR ce.valuenum > 180) THEN 1
        WHEN v.label = 'Diastolic blood pressure' AND (ce.valuenum < 60 OR ce.valuenum > 110) THEN 1
        WHEN v.label = 'Respiratory rate' AND (ce.valuenum < 8 OR ce.valuenum > 30) THEN 1
        WHEN v.label = 'Temperature Fahrenheit' AND (ce.valuenum < 95 OR ce.valuenum > 101.3) THEN 1
        WHEN v.label = 'O2 saturation pulseoxymetry' AND ce.valuenum < 90 THEN 1
        ELSE 0
      END
    ) AS instability_score
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ep.stay_id = ce.stay_id
  JOIN vitals v
    ON ce.itemid = v.itemid
  WHERE ce.charttime >= ep.intime
    AND ce.charttime <= DATETIME_ADD(ep.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ep.stay_id
),

score_percentiles AS (
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY instability_score) AS percentile_rank,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM vital_scores
)

-- Final output
SELECT
  -- Percentile of score 70
  (SELECT MAX(percentile_rank) FROM score_percentiles WHERE instability_score <= 70) AS percentile_of_70,

  -- Mean LOS and mortality for top decile
  AVG(CASE WHEN decile = 1 THEN los ELSE NULL END) AS mean_los_top_decile,
  AVG(CASE WHEN decile = 1 THEN hospital_expire_flag ELSE NULL END) AS mortality_top_decile
FROM score_percentiles
JOIN eligible_patients ep ON score_percentiles.stay_id = ep.stay_id;