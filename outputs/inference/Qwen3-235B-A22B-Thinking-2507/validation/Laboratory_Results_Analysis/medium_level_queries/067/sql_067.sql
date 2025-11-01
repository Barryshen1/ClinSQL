WITH ami_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
    )
),
ami_admissions_with_age AS (
  SELECT 
    *,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM ami_admissions
),
filtered_ami_admissions AS (
  SELECT *
  FROM ami_admissions_with_age
  WHERE age_at_admission BETWEEN 52 AND 62
),
first_troponin_in_cohort AS (
  SELECT 
    ft.hadm_id,
    ft.valuenum
  FROM (
    SELECT 
      le.hadm_id,
      le.charttime,
      le.valuenum,
      ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
      ON le.itemid = dli.itemid
    WHERE dli.label LIKE '%TROPONIN T%'
      AND le.valuenum IS NOT NULL
  ) ft
  INNER JOIN filtered_ami_admissions fa
    ON ft.hadm_id = fa.hadm_id
  WHERE ft.charttime >= fa.admittime
    AND ft.charttime <= fa.dischtime
    AND ft.rn = 1
),
cohort AS (
  SELECT 
    fa.*,
    ft.valuenum AS first_troponin_value
  FROM filtered_ami_admissions fa
  INNER JOIN first_troponin_in_cohort ft
    ON fa.hadm_id = ft.hadm_id
  WHERE ft.valuenum > 0.01
)
SELECT
  COUNT(DISTINCT subject_id) AS num_patients,
  COUNT(*) AS num_admissions,
  AVG(age_at_admission) AS mean_age,
  AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
  COUNT(first_troponin_value) AS num_first_troponin,
  MIN(first_troponin_value) AS min_first_troponin,
  MAX(first_troponin_value) AS max_first_troponin,
  AVG(first_troponin_value) AS avg_first_troponin,
  STDDEV(first_troponin_value) AS std_first_troponin,
  SUM(hospital_expire_flag) AS deaths,
  AVG(hospital_expire_flag) AS mortality_rate
FROM cohort;