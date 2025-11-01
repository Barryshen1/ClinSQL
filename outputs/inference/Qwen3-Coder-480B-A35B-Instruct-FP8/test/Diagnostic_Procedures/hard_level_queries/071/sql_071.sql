WITH target_cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) AS hospital_los,
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
    AND (
      (d_dx.icd_version = 9 AND d_dx.icd_code = '431')
      OR
      (d_dx.icd_version = 10 AND d_dx.icd_code LIKE 'I61%')
    )
),

procedure_counts_target AS (
  SELECT
    tc.stay_id,
    tc.hospital_los,
    tc.hospital_expire_flag,
    COUNT(proc.stay_id) AS proc_count
  FROM
    target_cohort tc
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents proc
    ON tc.stay_id = proc.stay_id
    AND proc.starttime >= tc.intime
    AND proc.starttime <= DATETIME_ADD(tc.intime, INTERVAL 72 HOUR)
  GROUP BY
    tc.stay_id, tc.hospital_los, tc.hospital_expire_flag
),

target_stats AS (
  SELECT
    'Target (Female 50-60 with ICH)' AS cohort,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS proc_25th,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(50)] AS proc_median,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS proc_90th,
    MAX(proc_count) AS proc_max,
    AVG(hospital_los) AS avg_hosp_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    procedure_counts_target
),

icu_times AS (
  SELECT
    stay_id,
    intime
  FROM
    physionet-data.mimiciv_3_1_icu.icustays
),

general_icu AS (
  SELECT
    icu.stay_id,
    icu.intime,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) AS hospital_los,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
),

procedure_counts_general AS (
  SELECT
    gi.stay_id,
    gi.hospital_los,
    gi.hospital_expire_flag,
    COUNT(proc.stay_id) AS proc_count
  FROM
    general_icu gi
  LEFT JOIN
    icu_times icu_t
    ON gi.stay_id = icu_t.stay_id
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents proc
    ON gi.stay_id = proc.stay_id
    AND proc.starttime >= icu_t.intime
    AND proc.starttime <= DATETIME_ADD(icu_t.intime, INTERVAL 72 HOUR)
  GROUP BY
    gi.stay_id, gi.hospital_los, gi.hospital_expire_flag
),

general_stats AS (
  SELECT
    'General ICU' AS cohort,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS proc_25th,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(50)] AS proc_median,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS proc_90th,
    MAX(proc_count) AS proc_max,
    AVG(hospital_los) AS avg_hosp_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    procedure_counts_general
)

SELECT * FROM target_stats
UNION ALL
SELECT * FROM general_stats;