WITH ich_cohort AS (
  SELECT DISTINCT
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 56 AND 66
    AND LOWER(dicd.long_title) LIKE '%intracranial hemorrhage%'
),

diagnostic_intensity AS (
  SELECT
    ic.stay_id,
    COUNT(l.labevent_id) + COUNT(m.microevent_id) AS diagnostic_events
  FROM ich_cohort ic
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON ic.subject_id = l.subject_id AND ic.hadm_id = l.hadm_id
    AND l.charttime >= ic.intime
    AND l.charttime <= ic.intime + INTERVAL '72' HOUR
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` m
    ON ic.subject_id = m.subject_id AND ic.hadm_id = m.hadm_id
    AND m.charttime >= ic.intime
    AND m.charttime <= ic.intime + INTERVAL '72' HOUR
  GROUP BY ic.stay_id
),

ich_summary AS (
  SELECT
    PERCENTILE_CONT(di.diagnostic_events, 0.95) WITHIN GROUP (ORDER BY di.diagnostic_events) AS ich_95th_diagnostic_intensity,
    AVG(ic.los) AS ich_avg_los,
    AVG(ic.hospital_expire_flag) AS ich_mortality_rate
  FROM ich_cohort ic
  LEFT JOIN diagnostic_intensity di ON ic.stay_id = di.stay_id
),

overall_icu_summary AS (
  SELECT
    AVG(los) AS overall_avg_los,
    AVG(hospital_expire_flag) AS overall_mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
)

SELECT
  i.ich_95th_diagnostic_intensity,
  i.ich_avg_los,
  i.ich_mortality_rate,
  o.overall_avg_los,
  o.overall_mortality_rate
FROM ich_summary i
CROSS JOIN overall_icu_summary o;