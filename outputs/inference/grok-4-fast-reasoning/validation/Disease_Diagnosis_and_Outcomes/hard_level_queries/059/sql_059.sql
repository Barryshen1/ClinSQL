WITH base_patients AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 59 AND 69
),
dka_hadms AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN base_patients bp ON di.subject_id = bp.subject_id
  WHERE (di.icd_version = 10 AND di.icd_code IN ('E10.10', 'E10.11', 'E11.10', 'E11.11', 'E13.10', 'E13.11'))
     OR (di.icd_version = 9 AND di.icd_code LIKE '250.1%')
),
aki_hadms AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN base_patients bp ON di.subject_id = bp.subject_id
  WHERE (di.icd_version = 10 AND di.icd_code LIKE 'N17.%')
     OR (di.icd_version = 9 AND di.icd_code LIKE '584.%')
),
ards_hadms AS (
  SELECT DISTINCT di.subject_id, di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN base_patients bp ON di.subject_id = bp.subject_id
  WHERE (di.icd_version = 10 AND di.icd_code = 'J80')
     OR (di.icd_version = 9 AND di.icd_code = '518.82')
),
admissions_base AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.dod
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN base_patients bp ON a.subject_id = bp.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
),
full_cohort AS (
  SELECT
    ab.subject_id,
    ab.hadm_id,
    ab.admittime,
    ab.dischtime,
    ab.hospital_expire_flag,
    ab.dod,
    CASE WHEN dh.hadm_id IS NOT NULL THEN 'DKA' ELSE 'General' END AS cohort_type,
    CASE
      WHEN ab.dod IS NOT NULL
       AND DATE(ab.dod) <= DATE_ADD(DATE(ab.admittime), INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS died_30d,
    CASE
      WHEN ab.dod IS NULL OR DATE(ab.dod) > DATE_ADD(DATE(ab.admittime), INTERVAL 30 DAY)
      THEN DATE_DIFF(DATE(ab.dischtime), DATE(ab.admittime), DAY)
      ELSE NULL
    END AS survivor_los,
    CASE WHEN ah.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki,
    CASE WHEN ar.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards
  FROM admissions_base ab
  LEFT JOIN dka_hadms dh ON ab.hadm_id = dh.hadm_id
  LEFT JOIN aki_hadms ah ON ab.hadm_id = ah.hadm_id
  LEFT JOIN ards_hadms ar ON ab.hadm_id = ar.hadm_id
),
metrics AS (
  SELECT
    cohort_type,
    ROUND(AVG(died_30d * 1.0), 4) AS mort_30d_rate,
    ROUND(AVG(has_aki * 1.0), 4) AS aki_rate,
    ROUND(AVG(has_ards * 1.0), 4) AS ards_rate,
    ROUND(AVG(survivor_los), 1) AS mean_survivor_los,
    COUNT(*) AS n
  FROM full_cohort
  GROUP BY cohort_type
)
SELECT
  cohort_type,
  mort_30d_rate,
  aki_rate,
  ards_rate,
  mean_survivor_los,
  n
FROM metrics
ORDER BY CASE WHEN cohort_type = 'DKA' THEN 1 ELSE 2 END;