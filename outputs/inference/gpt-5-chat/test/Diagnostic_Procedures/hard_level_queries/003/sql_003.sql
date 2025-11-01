WITH base_icu AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    p.gender,
    p.anchor_age,
    icu.intime,
    icu.outtime,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
),
ards_cases AS (
  SELECT DISTINCT b.subject_id, b.hadm_id
  FROM base_icu b
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON b.subject_id = d.subject_id
    AND b.hadm_id = d.hadm_id
  WHERE (d.icd_version = 9 AND d.icd_code = '51882')
     OR (d.icd_version = 10 AND d.icd_code = 'J80')
),
procedures_first24h AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    b.stay_id,
    COUNT(DISTINCT pr.icd_code) AS proc_count_24h
  FROM base_icu b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON b.subject_id = pr.subject_id
    AND b.hadm_id = pr.hadm_id
    AND pr.chartdate BETWEEN DATE(b.intime) 
                         AND DATE(TIMESTAMP_ADD(b.intime, INTERVAL 1 DAY))
  GROUP BY b.subject_id, b.hadm_id, b.stay_id
),
cohort_metrics AS (
  SELECT
    CASE
      WHEN b.gender = 'F' AND b.anchor_age BETWEEN 84 AND 94 AND ac.subject_id IS NOT NULL THEN 'Female_84_94_ARDS'
      ELSE 'General_ICU'
    END AS cohort,
    proc.proc_count_24h,
    TIMESTAMP_DIFF(b.dischtime, b.admittime, DAY) AS hosp_los_days,
    b.hospital_expire_flag
  FROM base_icu b
  LEFT JOIN ards_cases ac
    ON b.subject_id = ac.subject_id AND b.hadm_id = ac.hadm_id
  LEFT JOIN procedures_first24h proc
    ON b.subject_id = proc.subject_id AND b.hadm_id = proc.hadm_id AND b.stay_id = proc.stay_id
),
quantiles_per_cohort AS (
  SELECT
    cohort,
    APPROX_QUANTILES(proc_count_24h, 100) AS quantiles,
    AVG(hosp_los_days) AS avg_hosp_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort_metrics
  GROUP BY cohort
)
SELECT
  cohort,
  quantiles[OFFSET(ROUND(0.25 * (ARRAY_LENGTH(quantiles) - 1)))] AS q25,
  quantiles[OFFSET(ROUND(0.75 * (ARRAY_LENGTH(quantiles) - 1)))] AS q75,
  quantiles[OFFSET(ROUND(0.95 * (ARRAY_LENGTH(quantiles) - 1)))] AS q95,
  avg_hosp_los_days,
  mortality_rate
FROM quantiles_per_cohort
ORDER BY cohort;