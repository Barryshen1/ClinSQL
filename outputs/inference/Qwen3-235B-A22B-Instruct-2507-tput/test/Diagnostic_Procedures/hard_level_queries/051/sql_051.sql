WITH patients_sepsis AS (
  SELECT DISTINCT a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%sepsis%'
),
cohort_stays AS (
  SELECT 
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.intime,
    s.outtime,
    s.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu`.icustays s
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON s.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  JOIN patients_sepsis ps ON p.subject_id = ps.subject_id
  WHERE p.anchor_age BETWEEN 90 AND 100
    AND p.gender = 'M'
),
diagnostic_counts AS (
  SELECT
    cs.stay_id,
    cs.hospital_expire_flag,
    cs.los,
    COALESCE(COUNT(DISTINCT le.labevent_id), 0) AS lab_count,
    COALESCE(COUNT(DISTINCT me.microevent_id), 0) AS micro_count,
    COALESCE(COUNT(DISTINCT STRUCT(ce.charttime, ce.itemid)), 0) AS chart_count,
    COALESCE(COUNT(DISTINCT STRUCT(pe.starttime, pe.itemid)), 0) AS proc_count,
    (COALESCE(COUNT(DISTINCT le.labevent_id), 0) +
     COALESCE(COUNT(DISTINCT me.microevent_id), 0) +
     COALESCE(COUNT(DISTINCT STRUCT(ce.charttime, ce.itemid)), 0) +
     COALESCE(COUNT(DISTINCT STRUCT(pe.starttime, pe.itemid)), 0)
    ) AS diagnostic_utilization
  FROM cohort_stays cs
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON cs.hadm_id = le.hadm_id 
    AND le.charttime >= cs.intime 
    AND le.charttime < DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.microbiologyevents me
    ON cs.hadm_id = me.hadm_id
    AND me.charttime >= cs.intime
    AND me.charttime < DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON cs.stay_id = ce.stay_id
    AND ce.charttime >= cs.intime
    AND ce.charttime < DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.procedureevents pe
    ON cs.stay_id = pe.stay_id
    AND pe.starttime >= cs.intime
    AND pe.starttime < DATETIME_ADD(cs.intime, INTERVAL 24 HOUR)
  GROUP BY cs.stay_id, cs.hospital_expire_flag, cs.los
),
aggregates AS (
  SELECT
    STDDEV(diagnostic_utilization) AS sd_diagnostic_utilization,
    APPROX_QUANTILES(diagnostic_utilization, 1000 IGNORE NULLS)[OFFSET(750)] AS p75_diagnostic_utilization,
    APPROX_QUANTILES(diagnostic_utilization, 1000 IGNORE NULLS)[OFFSET(950)] AS p95_diagnostic_utilization,
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct,
    AVG(los) AS avg_los,
    COUNT(*) AS cohort_icu_admissions
  FROM diagnostic_counts
)
SELECT
  sd_diagnostic_utilization,
  p75_diagnostic_utilization,
  p95_diagnostic_utilization,
  in_hospital_mortality_pct,
  avg_los,
  cohort_icu_admissions,
  (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_icu`.icustays) AS total_icu
FROM aggregates;