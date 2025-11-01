WITH all_icu_stays AS (
  SELECT 
    i.stay_id,
    i.hadm_id,
    i.subject_id,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
),

lab_counts AS (
  SELECT
    i.stay_id,
    COUNT(l.labevent_id) AS lab_count
  FROM all_icu_stays i
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON i.hadm_id = l.hadm_id
    AND i.subject_id = l.subject_id
    AND l.charttime >= i.intime
    AND l.charttime <= i.intime + INTERVAL '72 hours'
    AND l.charttime <= i.outtime
  GROUP BY i.stay_id
),

heart_failure_cohort AS (
  SELECT 
    a.stay_id,
    a.hadm_id,
    a.subject_id,
    a.icu_los,
    a.hospital_expire_flag,
    l.lab_count
  FROM all_icu_stays a
  JOIN lab_counts l ON a.stay_id = l.stay_id
  WHERE 
    a.gender = 'M'
    AND a.anchor_age BETWEEN 70 AND 80
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

general_icu_population AS (
  SELECT 
    a.stay_id,
    a.hadm_id,
    a.subject_id,
    a.icu_los,
    a.hospital_expire_flag,
    l.lab_count
  FROM all_icu_stays a
  JOIN lab_counts l ON a.stay_id = l.stay_id
)

SELECT 
  'Heart Failure Cohort' AS group_name,
  AVG(lab_count) AS mean_lab_count,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY lab_count) AS median_lab_count,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lab_count) AS p75_lab_count,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY lab_count) AS p95_lab_count,
  AVG(icu_los) AS mean_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality
FROM heart_failure_cohort

UNION ALL

SELECT 
  'General ICU Population' AS group_name,
  AVG(lab_count) AS mean_lab_count,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY lab_count) AS median_lab_count,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY lab_count) AS p75_lab_count,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY lab_count) AS p95_lab_count,
  AVG(icu_los) AS mean_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality
FROM general_icu_population;