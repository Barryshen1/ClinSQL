WITH ards_cohort AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE d_dx.icd_code IN ('51881', 'J80')
),
icu_population AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    pat.gender,
    pat.anchor_age,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hosp_los_days
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
),
procedure_counts AS (
  SELECT
    proc.stay_id,
    COUNT(DISTINCT proc.itemid) AS distinct_procedures
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` proc
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON proc.stay_id = icu.stay_id
  WHERE proc.starttime >= icu.intime
    AND proc.starttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY proc.stay_id
),
ards_group AS (
  SELECT
    'ARDS Female 84-94' AS cohort,
    pc.distinct_procedures,
    ip.hosp_los_days,
    ip.hospital_expire_flag
  FROM icu_population ip
  JOIN ards_cohort ards
    ON ip.stay_id = ards.stay_id
  LEFT JOIN procedure_counts pc
    ON ip.stay_id = pc.stay_id
  WHERE ip.gender = 'F'
    AND ip.anchor_age BETWEEN 84 AND 94
),
general_group AS (
  SELECT
    'General ICU' AS cohort,
    pc.distinct_procedures,
    ip.hosp_los_days,
    ip.hospital_expire_flag
  FROM icu_population ip
  LEFT JOIN procedure_counts pc
    ON ip.stay_id = pc.stay_id
),
combined AS (
  SELECT * FROM ards_group
  UNION ALL
  SELECT * FROM general_group
)
SELECT
  cohort,
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(25)] AS p25_distinct_procedures,
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(75)] AS p75_distinct_procedures,
  APPROX_QUANTILES(distinct_procedures, 100)[OFFSET(95)] AS p95_distinct_procedures,
  AVG(hosp_los_days) AS avg_hosp_los_days,
  AVG(hospital_expire_flag) AS hospital_mortality_rate
FROM combined
GROUP BY cohort
ORDER BY cohort;