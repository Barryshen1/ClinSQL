WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
    AND (
      d.icd_code = '431'
      OR d.icd_code LIKE 'I61%'
      OR d.icd_code LIKE 'I62%'
      OR did.long_title LIKE '%hemorrhagic%'
      OR did.long_title LIKE '%intracerebral hemorrhage%'
      OR did.long_title LIKE '%intracranial hemorrhage%'
    )
),

general_cohort AS (
  SELECT DISTINCT
    p.subject_id,
    p.anchor_age,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.anchor_age >= 18
),

lab_events_48h AS (
  -- Chartevents: physiologic measurements with normal ranges in d_items
  SELECT
    ce.stay_id,
    1 AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON ce.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    AND di.lownormalvalue IS NOT NULL
    AND di.highnormalvalue IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime <= i.intime + INTERVAL '48 hours'
    AND (ce.valuenum < di.lownormalvalue OR ce.valuenum > di.highnormalvalue)

  UNION ALL

  -- Labevents: lab tests with normal ranges in d_labitems
  SELECT
    i.stay_id,
    1 AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE le.valuenum IS NOT NULL
    AND dl.ref_range_lower IS NOT NULL
    AND dl.ref_range_upper IS NOT NULL
    AND le.charttime >= i.intime
    AND le.charttime <= i.intime + INTERVAL '48 hours'
    AND (le.valuenum < dl.ref_range_lower OR le.valuenum > dl.ref_range_upper)
),

instability_scores AS (
  SELECT
    stay_id,
    COUNT(*) AS instability_score
  FROM lab_events_48h
  GROUP BY stay_id
),

cohort_with_scores AS (
  SELECT
    c.stay_id,
    COALESCE(is.instability_score, 0) AS instability_score,
    c.los,
    c.hospital_expire_flag
  FROM cohort c
  LEFT JOIN instability_scores is ON c.stay_id = is.stay_id
),

general_with_scores AS (
  SELECT
    c.stay_id,
    COALESCE(is.instability_score, 0) AS instability_score,
    c.los,
    c.hospital_expire_flag
  FROM general_cohort c
  LEFT JOIN instability_scores is ON c.stay_id = is.stay_id
)

SELECT
  PERCENTILE_CONT(cohort_with_scores.instability_score, 0.25) AS pct25_instability_score_cohort,
  AVG(general_with_scores.instability_score) AS mean_instability_score_general,
  AVG(cohort_with_scores.los) AS mean_los_cohort,
  AVG(general_with_scores.los) AS mean_los_general,
  AVG(CAST(cohort_with_scores.hospital_expire_flag AS FLOAT64)) AS mortality_rate_cohort,
  AVG(CAST(general_with_scores.hospital_expire_flag AS FLOAT64)) AS mortality_rate_general
FROM cohort_with_scores, general_with_scores;