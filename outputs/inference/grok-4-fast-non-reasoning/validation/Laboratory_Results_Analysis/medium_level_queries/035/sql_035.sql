WITH qualified_labs AS (
  SELECT DISTINCT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.label = 'hsTnT'
    AND le.valuenum > 14
    AND le.valueuom = 'ng/mL'
    AND le.valuenum IS NOT NULL
),
first_troponin AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_charttime
  FROM qualified_labs
  GROUP BY subject_id, hadm_id
),
cohort AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN first_troponin ft
    ON a.subject_id = ft.subject_id AND a.hadm_id = ft.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND ft.first_charttime >= a.admittime  -- Ensure lab during admission
)
SELECT
  COUNT(DISTINCT hadm_id) AS cohort_size,
  AVG(DATE_DIFF(DATE(dischtime), DATE(admittime), DAY)) AS avg_los_days,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_pct
FROM cohort;