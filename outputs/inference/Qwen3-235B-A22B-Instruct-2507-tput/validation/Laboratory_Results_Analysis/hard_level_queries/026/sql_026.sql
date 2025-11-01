WITH
  critical_lab_items AS (
    SELECT DISTINCT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE LOWER(label) LIKE '%lactate%'
       OR LOWER(label) LIKE '%ammonia%'
       OR LOWER(label) LIKE '%inr%'
       OR LOWER(label) LIKE '%bilirubin%'
       OR LOWER(label) LIKE '%creatinine%'
       OR LOWER(label) LIKE '%alt%'
       OR LOWER(label) LIKE '%ast%'
       OR LOWER(label) LIKE '%alp%'
       OR LOWER(label) LIKE '%pt%'
       OR LOWER(label) LIKE '%ptt%'
  ),
  patients_cohort AS (
    SELECT
      p.subject_id,
      p.gender,
      p.anchor_age,
      CASE
        WHEN di.icd_code IS NOT NULL THEN 1
        ELSE 0
      END AS has_hepatic_failure
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      ON p.subject_id = di.subject_id
     AND di.icd_version = 10
     AND di.icd_code LIKE 'K72%'
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 75 AND 85
  ),
  admissions_cohort AS (
    SELECT
      a.hadm_id,
      a.subject_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 3600) AS los_days,
      pc.has_hepatic_failure
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN patients_cohort pc
      ON a.subject_id = pc.subject_id
  ),
  critical_labs_48h AS (
    SELECT
      le.hadm_id,
      COUNT(*) AS critical_lab_count
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN critical_lab_items cli
      ON le.itemid = cli.itemid
    INNER JOIN admissions_cohort ac
      ON le.hadm_id = ac.hadm_id
    WHERE le.charttime >= ac.admittime
      AND le.charttime <= DATETIME_ADD(ac.admittime, INTERVAL 48 HOUR)
    GROUP BY le.hadm_id
  ),
  cohort_stats AS (
    SELECT
      ac.has_hepatic_failure,
      COUNT(*) AS admission_count,
      AVG(CAST(ac.hospital_expire_flag AS FLOAT64)) AS mortality_rate,
      AVG(ac.los_days) AS avg_los,
      AVG(COALESCE(cl.critical_lab_count, 0)) AS avg_critical_labs_48h
    FROM admissions_cohort ac
    LEFT JOIN critical_labs_48h cl
      ON ac.hadm_id = cl.hadm_id
    GROUP BY ac.has_hepatic_failure
  )
SELECT
  CASE
    WHEN has_hepatic_failure = 1 THEN 'Hepatic Failure Cohort'
    ELSE 'General Inpatient Cohort (Same Age/Gender)'
  END AS patient_group,
  mortality_rate,
  avg_los,
  avg_critical_labs_48h
FROM cohort_stats
ORDER BY has_hepatic_failure DESC;