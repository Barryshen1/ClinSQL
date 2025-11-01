WITH cohort AS (
  SELECT DISTINCT
    i.stay_id,
    i.hadm_id,
    i.intime,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON i.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
    AND (
      (d.icd_version = '9' AND d.icd_code IN ('430', '431', '432'))
      OR
      (d.icd_version = '10' AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%'))
    )
),

cohort_lab_events AS (
  SELECT
    c.stay_id,
    COUNT(l.labevent_id) AS lab_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)
  GROUP BY c.stay_id
),

cohort_metrics AS (
  SELECT
    PERCENTILE_CONT(lab_count, 0.95) WITHIN GROUP (ORDER BY lab_count) AS cohort_95th_diagnostic_intensity,
    AVG(c.los) AS cohort_avg_los,
    AVG(c.hospital_expire_flag) AS cohort_mortality_rate
  FROM cohort c
  LEFT JOIN cohort_lab_events l ON c.stay_id = l.stay_id
),

overall_metrics AS (
  SELECT
    AVG(i.los) AS overall_avg_los,
    AVG(a.hospital_expire_flag) AS overall_mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
)

SELECT
  cm.cohort_95th_diagnostic_intensity,
  cm.cohort_avg_los,
  cm.cohort_mortality_rate,
  om.overall_avg_los,
  om.overall_mortality_rate
FROM cohort_metrics cm, overall_metrics om;