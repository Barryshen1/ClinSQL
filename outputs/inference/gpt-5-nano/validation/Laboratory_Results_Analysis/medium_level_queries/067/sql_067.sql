WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dicd
    ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE
    p.gender = 'Female'
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
    -- Age at admission between 52 and 62 inclusive
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 52 AND 62
    -- AMI: myocardial infarction (ICD long title)
    AND LOWER(dicd.long_title) LIKE '%myocardial infarction%'
),
first_troponin AS (
  SELECT
    lv.hadm_id,
    lv.subject_id,
    (ARRAY_AGG(lv.valuenum ORDER BY lv.charttime ASC LIMIT 1))[OFFSET(0)] AS first_troponin_valuenum,
    (ARRAY_AGG(lv.charttime ORDER BY lv.charttime ASC LIMIT 1))[OFFSET(0)] AS first_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS lv
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON lv.itemid = dli.itemid
  WHERE
    (
      LOWER(dli.label) LIKE '%troponin t%'
      OR LOWER(dli.label) LIKE '%troponin_t%'
    )
  GROUP BY lv.hadm_id, lv.subject_id
)
SELECT
  COUNT(DISTINCT c.subject_id) AS patient_count,
  COUNT(DISTINCT c.hadm_id) AS admission_count,
  AVG(c.age_at_adm) AS mean_age_at_admission,
  AVG(c.los_days) AS mean_los_days,
  AVG(ft.first_troponin_valuenum) AS first_troponin_valuenum_avg,
  MIN(ft.first_troponin_valuenum) AS first_troponin_valuenum_min,
  MAX(ft.first_troponin_valuenum) AS first_troponin_valuenum_max,
  MIN(ft.first_charttime) AS first_troponin_charttime_min,
  AVG(CASE WHEN c.hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS in_hospital_mortality_rate
FROM cohort AS c
JOIN first_troponin AS ft
  ON c.subject_id = ft.subject_id
  AND c.hadm_id = ft.hadm_id
WHERE ft.first_troponin_valuenum > 0.01;