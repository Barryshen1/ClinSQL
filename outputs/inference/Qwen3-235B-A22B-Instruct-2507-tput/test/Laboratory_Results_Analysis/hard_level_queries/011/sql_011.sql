WITH age_filtered AS (
  SELECT
    p.subject_id,
    p.gender,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admit,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 47 AND 57
),

aki_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (icd_version = 10 AND icd_code LIKE 'N17%')
     OR (icd_version = 9 AND icd_code = '584')
),

aki_cohort AS (
  SELECT DISTINCT af.*
  FROM age_filtered af
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON af.hadm_id = di.hadm_id
  JOIN aki_codes ac
    ON di.icd_code = ac.icd_code AND di.icd_version = (CASE WHEN ac.icd_code LIKE 'N17%' THEN 10 ELSE 9 END)
),

non_aki_cohort AS (
  SELECT af.*
  FROM age_filtered af
  LEFT JOIN aki_cohort ak ON af.hadm_id = ak.hadm_id
  WHERE ak.hadm_id IS NULL
),

-- Lab events in first 72 hours
labs_72h AS (
  SELECT
    le.hadm_id,
    di.label,
    le.valuenum
  FROM
    `physionet-data.mimiciv_3_1_hosp`.labevents le
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_labitems di
  ON
    le.itemid = di.itemid
  JOIN
    age_filtered af
  ON
    le.hadm_id = af.hadm_id
  WHERE
    le.charttime >= af.admittime
    AND le.charttime <= DATETIME_ADD(af.admittime, INTERVAL 72 HOUR)
    AND di.label IN ('Creatinine', 'Potassium', 'Sodium')
    AND le.valuenum IS NOT NULL
),

-- Compute CV (coefficient of variation) per admission
lab_stats AS (
  SELECT
    hadm_id,
    AVG(valuenum) AS mean_value,
    STDDEV(valuenum) AS std_value
  FROM labs_72h
  GROUP BY hadm_id
  HAVING COUNT(*) >= 2  -- At least 2 labs to compute variability
),

lab_instability AS (
  SELECT
    hadm_id,
    (std_value / NULLIF(mean_value, 0)) * 100 AS cv_percent  -- Coefficient of variation
  FROM lab_stats
),

-- ICU admission flag
icu_stays AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
),

cohort_outcomes AS (
  SELECT
    'AKI' AS group_label,
    aki.hadm_id,
    aki.hospital_expire_flag,
    DATETIME_DIFF(aki.dischtime, aki.admittime, SECOND) / (24*60*60) AS los_days,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_admission,
    li.cv_percent
  FROM aki_cohort aki
  LEFT JOIN icu_stays icu ON aki.hadm_id = icu.hadm_id
  LEFT JOIN lab_instability li ON aki.hadm_id = li.hadm_id

  UNION ALL

  SELECT
    'Non-AKI' AS group_label,
    nonaki.hadm_id,
    nonaki.hospital_expire_flag,
    DATETIME_DIFF(nonaki.dischtime, nonaki.admittime, SECOND) / (24*60*60) AS los_days,
    CASE WHEN icu.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS icu_admission,
    li.cv_percent
  FROM non_aki_cohort nonaki
  LEFT JOIN icu_stays icu ON nonaki.hadm_id = icu.hadm_id
  LEFT JOIN lab_instability li ON nonaki.hadm_id = li.hadm_id
)

SELECT
  group_label,
  AVG(cv_percent) AS mean_72h_lab_instability_score,
  AVG(icu_admission) AS prop_icu_admission,
  AVG(los_days) AS avg_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate
FROM cohort_outcomes
GROUP BY group_label
ORDER BY group_label;