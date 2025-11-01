WITH ich_cohort AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.intime,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON d.hadm_id = i.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON d.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND d.icd_version = 10
    AND (d.icd_code LIKE 'I60%' OR d.icd_code LIKE 'I61%' OR d.icd_code LIKE 'I62%')
    AND dd.long_title LIKE '%hemorrhage%'
),

procedure_counts AS (
  SELECT
    i.stay_id,
    COUNT(pe.itemid) AS procedure_count
  FROM ich_cohort i
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON i.stay_id = pe.stay_id
    AND pe.starttime >= i.intime
    AND pe.starttime <= i.intime + INTERVAL '72' HOUR
  GROUP BY i.stay_id
),

ich_procedure_stats AS (
  SELECT
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(90)] AS p90,
    MAX(procedure_count) AS max_procedure
  FROM procedure_counts
),

ich_los_mortality AS (
  SELECT
    AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM ich_cohort
),

general_icu AS (
  SELECT
    a.hadm_id,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  GROUP BY a.hadm_id, a.dischtime, a.admittime, a.hospital_expire_flag
),

general_los_mortality AS (
  SELECT
    AVG(los_days) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM general_icu
)

SELECT
  p.p25,
  p.p50,
  p.p90,
  p.max_procedure,
  i.avg_los AS ich_avg_los,
  i.mortality_rate AS ich_mortality_rate,
  g.avg_los AS general_avg_los,
  g.mortality_rate AS general_mortality_rate
FROM ich_procedure_stats p
CROSS JOIN ich_los_mortality i
CROSS JOIN general_los_mortality g;