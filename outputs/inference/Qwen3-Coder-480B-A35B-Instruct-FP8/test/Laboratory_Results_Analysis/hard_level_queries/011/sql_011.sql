WITH cohort AS (
  -- Define base cohort: male patients aged 47–57
  SELECT
    p.subject_id,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag,
    MAX(CASE WHEN d.long_title LIKE '%acute kidney injury%' THEN 1 ELSE 0 END) AS has_aki
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 47 AND 57
  GROUP BY
    p.subject_id, a.hadm_id, i.stay_id, i.intime, i.outtime, i.los, a.hospital_expire_flag
),

-- Identify AKI patients
aki_patients AS (
  SELECT DISTINCT subject_id
  FROM cohort
  WHERE has_aki = 1
),

-- Assign cohort type: AKI vs Control
labeled_cohort AS (
  SELECT
    c.*,
    CASE
      WHEN ap.subject_id IS NOT NULL THEN 'AKI'
      ELSE 'Control'
    END AS cohort_type
  FROM
    cohort c
  LEFT JOIN
    aki_patients ap ON c.subject_id = ap.subject_id
),

-- Compute instability score: count of abnormal labs in first 72 hours of ICU stay
lab_instability AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.labevent_id,
    l.charttime,
    i.intime,
    i.stay_id,
    CASE
      WHEN l.flag = 'abnormal' THEN 1
      WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1
      ELSE 0
    END AS is_abnormal
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
      ON l.hadm_id = i.hadm_id
  WHERE
    l.charttime >= i.intime
    AND l.charttime <= DATETIME_ADD(i.intime, INTERVAL 72 HOUR)
    AND (l.flag = 'abnormal'
         OR l.valuenum < l.ref_range_lower
         OR l.valuenum > l.ref_range_upper)
),

-- Aggregate instability score per stay
instability_scores AS (
  SELECT
    stay_id,
    COUNT(*) AS instability_score
  FROM
    lab_instability
  GROUP BY
    stay_id
),

-- Final cohort with instability scores
final_cohort AS (
  SELECT
    lc.*,
    COALESCE(iscore.instability_score, 0) AS instability_score
  FROM
    labeled_cohort lc
  LEFT JOIN
    instability_scores iscore ON lc.stay_id = iscore.stay_id
)

-- Final aggregation
SELECT
  cohort_type,
  AVG(instability_score) AS mean_instability_score,
  COUNT(*) AS total_stays,
  AVG(los) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  SUM(instability_score) AS total_critical_events
FROM
  final_cohort
GROUP BY
  cohort_type
ORDER BY
  cohort_type;