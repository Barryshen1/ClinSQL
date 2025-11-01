WITH first_icu AS (
  SELECT 
    hadm_id, 
    MIN(intime) AS first_intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) / 24.0 AS hospital_los_days,
    icu.los AS icu_los_days,
    (
      SELECT COUNT(DISTINCT lab.itemid)
      FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
      WHERE lab.hadm_id = adm.hadm_id
        AND lab.charttime >= icu.intime
        AND lab.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    ) AS lab_count,
    (
      SELECT COUNT(DISTINCT micro.test_itemid)
      FROM `physionet-data.mimiciv_3_1_hosp.microbiologyevents` micro
      WHERE micro.hadm_id = adm.hadm_id
        AND micro.charttime IS NOT NULL
        AND micro.charttime >= icu.intime
        AND micro.charttime < DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    ) AS micro_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
  INNER JOIN first_icu
    ON icu.hadm_id = first_icu.hadm_id AND icu.intime = first_icu.first_intime
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 90 AND 100
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code IN ('99591', '99592', '78552'))
          OR
          (diag.icd_version = 10 AND diag.icd_code IN ('A41', 'R65.20', 'R65.21'))
        )
    )
),
cohort_with_diag AS (
  SELECT *,
    lab_count + micro_count AS diagnostic_count
  FROM cohort
),
agg AS (
  SELECT
    STDDEV(diagnostic_count) AS sd_diagnostic_utilization,
    AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_percent,
    AVG(hospital_los_days) AS avg_hospital_los_days,
    AVG(icu_los_days) AS avg_icu_los_days
  FROM cohort_with_diag
),
quantiles AS (
  SELECT
    approx_quantiles[OFFSET(75)] AS p75_diagnostic_utilization,
    approx_quantiles[OFFSET(95)] AS p95_diagnostic_utilization
  FROM (
    SELECT APPROX_QUANTILES(diagnostic_count, 100) AS approx_quantiles
    FROM cohort_with_diag
  )
)
SELECT
  sd_diagnostic_utilization,
  p75_diagnostic_utilization,
  p95_diagnostic_utilization,
  in_hospital_mortality_percent,
  avg_hospital_los_days,
  avg_icu_los_days
FROM agg
CROSS JOIN quantiles;