WITH base_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE (
    (di.icd_version = 9 AND di.icd_code LIKE '584%')
    OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
  )
  AND a.dischtime IS NOT NULL
),
cohort AS (
  SELECT
    *,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_adm
  FROM base_cohort
  WHERE gender = 'F'
    AND anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 52 AND 62
)
SELECT
  STDDEV(readmit_flag) AS per_encounter_std_dev_30d_readmission
FROM (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE a2.subject_id = cohort.subject_id
          AND a2.hadm_id <> cohort.hadm_id
          AND a2.admittime > cohort.dischtime
          AND a2.admittime <= TIMESTAMP_ADD(cohort.dischtime, INTERVAL 30 DAY)
      ) THEN 1
      ELSE 0
    END AS readmit_flag
  FROM cohort
);