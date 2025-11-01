WITH cohort AS (
  SELECT DISTINCT p.subject_id, adm.hadm_id, icu.stay_id, p.gender, p.anchor_age,
    icu.intime, icu.outtime, icu.los, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON diag.icd_code = ddi.icd_code AND diag.icd_version = ddi.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
    AND LOWER(ddi.long_title) LIKE '%pulmonary embolism%'
),
diagnostic_counts AS (
  SELECT c.stay_id,
    COUNT(DISTINCT le.labevent_id) AS num_labs,
    COUNT(DISTINCT me.microevent_id) AS num_micro
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.microbiologyevents` me
    ON c.hadm_id = me.hadm_id
    AND me.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
),
scores AS (
  SELECT c.*, (IFNULL(dc.num_labs,0) + IFNULL(dc.num_micro,0)) AS diag_score
  FROM cohort c
  LEFT JOIN diagnostic_counts dc
    ON c.stay_id = dc.stay_id
),
cohort_stats AS (
  SELECT
    percentile_cont(diag_score, 0.75) OVER() AS p75_diag_score,
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM scores
),
general_stats AS (
  SELECT
    AVG(los) AS avg_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
)
SELECT
  cs.p75_diag_score,
  cs.avg_los AS cohort_avg_los,
  gs.avg_los AS general_avg_los,
  cs.mortality_rate AS cohort_mortality_rate,
  gs.mortality_rate AS general_mortality_rate
FROM cohort_stats cs
CROSS JOIN general_stats gs
LIMIT 1;