WITH sepsis_icu_cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
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
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses ddx
    ON dx.icd_code = ddx.icd_code AND dx.icd_version = ddx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND LOWER(ddx.long_title) LIKE '%sepsis%'
),

first24_labevents AS (
  SELECT
    sicu.stay_id,
    COUNT(DISTINCT lab.labevent_id) AS lab_count
  FROM
    sepsis_icu_cohort sicu
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents lab
    ON sicu.hadm_id = lab.hadm_id
  WHERE
    lab.charttime >= sicu.intime
    AND lab.charttime <= DATETIME_ADD(sicu.intime, INTERVAL 24 HOUR)
  GROUP BY
    sicu.stay_id
),

first24_microevents AS (
  SELECT
    sicu.stay_id,
    COUNT(DISTINCT mic.microevent_id) AS micro_count
  FROM
    sepsis_icu_cohort sicu
  JOIN
    physionet-data.mimiciv_3_1_hosp.microbiologyevents mic
    ON sicu.hadm_id = mic.hadm_id
  WHERE
    mic.charttime >= sicu.intime
    AND mic.charttime <= DATETIME_ADD(sicu.intime, INTERVAL 24 HOUR)
  GROUP BY
    sicu.stay_id
),

diagnostic_counts AS (
  SELECT
    sicu.stay_id,
    COALESCE(lab.lab_count, 0) + COALESCE(mic.micro_count, 0) AS diagnostic_utilization
  FROM
    sepsis_icu_cohort sicu
  LEFT JOIN
    first24_labevents lab
    ON sicu.stay_id = lab.stay_id
  LEFT JOIN
    first24_microevents mic
    ON sicu.stay_id = mic.stay_id
)

SELECT
  STDDEV(diagnostic_utilization) AS sd_diagnostic_utilization,
  APPROX_QUANTILES(diagnostic_utilization, 100)[OFFSET(75)] AS p75_diagnostic_utilization,
  APPROX_QUANTILES(diagnostic_utilization, 100)[OFFSET(95)] AS p95_diagnostic_utilization,
  AVG(sicu.los) AS avg_los,
  AVG(sicu.hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
  COUNT(DISTINCT sicu.hadm_id) / COUNT(DISTINCT sicu.stay_id) AS admissions_per_icu_stay
FROM
  sepsis_icu_cohort sicu
LEFT JOIN
  diagnostic_counts dc
  ON sicu.stay_id = dc.stay_id;