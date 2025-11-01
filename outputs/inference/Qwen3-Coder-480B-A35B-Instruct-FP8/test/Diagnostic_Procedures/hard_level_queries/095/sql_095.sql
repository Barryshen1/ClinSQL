WITH cohort_patients AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.los,
    adm.hospital_expire_flag,
    icu.intime
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
    ON icu.hadm_id = dx.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 79 AND 89
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '415.1%')
      OR
      (dx.icd_version = 10 AND dx.icd_code LIKE 'I26%')
    )
),

diagnostic_procedures AS (
  SELECT
    proc.hadm_id,
    proc.subject_id,
    proc.chartdate,
    proc.icd_code,
    proc.icd_version,
    d_proc.long_title
  FROM
    physionet-data.mimiciv_3_1_hosp.procedures_icd proc
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_procedures d_proc
    ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
  WHERE
    LOWER(d_proc.long_title) LIKE '%diagnostic%'
),

procedure_in_24h AS (
  SELECT
    cp.stay_id,
    COUNT(DISTINCT dp.icd_code) AS diagnostic_utilization_score
  FROM
    cohort_patients cp
  JOIN
    diagnostic_procedures dp
    ON cp.hadm_id = dp.hadm_id
  WHERE
    dp.chartdate >= cp.intime
    AND dp.chartdate <= DATETIME_ADD(cp.intime, INTERVAL 1 DAY)
  GROUP BY
    cp.stay_id
),

cohort_stats AS (
  SELECT
    APPROX_QUANTILES(diagnostic_utilization_score, 100)[OFFSET(75)] AS percentile_75_score,
    AVG(los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    cohort_patients cp
  LEFT JOIN
    procedure_in_24h p24
    ON cp.stay_id = p24.stay_id
),

general_icu_stats AS (
  SELECT
    AVG(los) AS avg_icu_los_general,
    AVG(hospital_expire_flag) AS mortality_rate_general
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
)

SELECT
  cs.percentile_75_score,
  cs.avg_icu_los,
  cs.mortality_rate,
  gis.avg_icu_los_general,
  gis.mortality_rate_general
FROM
  cohort_stats cs
CROSS JOIN
  general_icu_stats gis;