WITH cohort_icu_stays AS (
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
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
    ON icu.hadm_id = dx.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 50 AND 60
    AND LOWER(d_dx.long_title) LIKE '%intracranial hemorrhage%'
),

procedure_counts AS (
  SELECT
    ci.stay_id,
    COUNT(proc.itemid) AS procedure_count
  FROM
    cohort_icu_stays ci
  JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents proc
    ON ci.stay_id = proc.stay_id
  WHERE
    proc.starttime >= ci.intime
    AND proc.starttime <= ci.intime + INTERVAL 72 HOUR
  GROUP BY
    ci.stay_id
),

percentiles AS (
  SELECT
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(25)] AS percentile_25,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(procedure_count, 100)[OFFSET(90)] AS percentile_90
  FROM
    procedure_counts
),

cohort_stats AS (
  SELECT
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    cohort_icu_stays
),

general_icu_stats AS (
  SELECT
    AVG(los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
)

SELECT
  p.percentile_25,
  p.median,
  p.percentile_90,
  c.avg_icu_los AS cohort_avg_icu_los,
  c.mortality_rate AS cohort_mortality_rate,
  g.avg_icu_los AS general_avg_icu_los,
  g.mortality_rate AS general_mortality_rate
FROM
  percentiles p,
  cohort_stats c,
  general_icu_stats g;