WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 38 AND 48
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
aki_admissions AS (
  SELECT DISTINCT pa.hadm_id
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_version = 10
    AND d.icd_code LIKE 'N17%'
),
admissions_with_icu_flag AS (
  SELECT
    pa.hadm_id,
    pa.los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu
  FROM patient_admissions pa
  JOIN aki_admissions aki ON pa.hadm_id = aki.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON pa.hadm_id = i.hadm_id
),
diagnostics_per_admission AS (
  SELECT
    awi.hadm_id,
    awi.los_days,
    awi.had_icu,
    COUNT(ce.charttime) AS diagnostic_count
  FROM admissions_with_icu_flag awi
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON awi.hadm_id = ce.hadm_id
  GROUP BY awi.hadm_id, awi.los_days, awi.had_icu
),
los_groups AS (
  SELECT
    hadm_id,
    diagnostic_count,
    had_icu,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group
  FROM diagnostics_per_admission
)
SELECT
  los_group,
  had_icu,
  AVG(diagnostic_count) AS mean_diagnostics,
  MIN(diagnostic_count) AS min_diagnostics,
  MAX(diagnostic_count) AS max_diagnostics
FROM los_groups
GROUP BY los_group, had_icu
ORDER BY los_group, had_icu;