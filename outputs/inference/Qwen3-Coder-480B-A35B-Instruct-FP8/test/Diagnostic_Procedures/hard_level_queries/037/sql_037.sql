WITH sepsis_cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
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
    AND pat.anchor_age BETWEEN 53 AND 63
    AND d_dx.icd_code IN ('99591', '99592', 'A41.9') -- Sepsis codes
),

sepsis_procedures AS (
  SELECT
    sp.stay_id,
    COUNT(proc.stay_id) AS proc_count
  FROM
    sepsis_cohort sp
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents proc
    ON sp.stay_id = proc.stay_id
    AND proc.starttime >= sp.intime
    AND proc.starttime <= sp.intime + INTERVAL 24 HOUR
  GROUP BY
    sp.stay_id
),

sepsis_stats AS (
  SELECT
    'Sepsis' AS cohort,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS percentile_75,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS percentile_90,
    AVG(icu_los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality
  FROM
    sepsis_cohort sc
  LEFT JOIN
    sepsis_procedures sp
    ON sc.stay_id = sp.stay_id
),

all_age_matched AS (
  SELECT DISTINCT
    icu.stay_id,
    icu.intime,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 53 AND 63
),

all_procedures AS (
  SELECT
    am.stay_id,
    COUNT(proc.stay_id) AS proc_count
  FROM
    all_age_matched am
  LEFT JOIN
    physionet-data.mimiciv_3_1_icu.procedureevents proc
    ON am.stay_id = proc.stay_id
    AND proc.starttime >= am.intime
    AND proc.starttime <= am.intime + INTERVAL 24 HOUR
  GROUP BY
    am.stay_id
),

all_stats AS (
  SELECT
    'All Age-Matched' AS cohort,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS percentile_75,
    APPROX_QUANTILES(proc_count, 100)[OFFSET(90)] AS percentile_90,
    AVG(icu_los) AS avg_icu_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality
  FROM
    all_age_matched am
  LEFT JOIN
    all_procedures ap
    ON am.stay_id = ap.stay_id
)

SELECT * FROM sepsis_stats
UNION ALL
SELECT * FROM all_stats;