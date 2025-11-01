WITH ich_cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
    ON icu.hadm_id = diag.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 56 AND 66
    AND LOWER(d_diag.long_title) LIKE '%intracranial hemorrhage%'
),

diagnostic_intensity AS (
  -- Count distinct diagnostic procedures and labs in first 72 hours
  SELECT
    icu.stay_id,
    COUNT(DISTINCT proc.seq_num) + COUNT(DISTINCT lab.labevent_id) AS diagnostic_count
  FROM
    ich_cohort icu
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.procedures_icd proc
    ON icu.hadm_id = proc.hadm_id
    AND proc.chartdate >= DATE(icu.intime)
    AND proc.chartdate <= DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
  LEFT JOIN
    physionet-data.mimiciv_3_1_hosp.labevents lab
    ON icu.hadm_id = lab.hadm_id
    AND lab.charttime >= icu.intime
    AND lab.charttime <= DATETIME_ADD(icu.intime, INTERVAL 72 HOUR)
  GROUP BY
    icu.stay_id
),

ich_stats AS (
  SELECT
    APPROX_QUANTILES(diagnostic_count, 100)[OFFSET(95)] AS diagnostic_intensity_95th,
    AVG(icu_los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM
    ich_cohort ich
  LEFT JOIN
    diagnostic_intensity di
    ON ich.stay_id = di.stay_id
),

icu_population AS (
  SELECT
    stay_id,
    los AS icu_los,
    hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
),

icu_stats AS (
  SELECT
    AVG(icu_los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM
    icu_population
)

SELECT
  ich_stats.diagnostic_intensity_95th,
  ich_stats.avg_icu_los AS ich_avg_icu_los,
  ich_stats.mortality_rate AS ich_mortality_rate,
  icu_stats.avg_icu_los AS icu_avg_icu_los,
  icu_stats.mortality_rate AS icu_mortality_rate
FROM
  ich_stats
CROSS JOIN
  icu_stats;