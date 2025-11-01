WITH hf_cohort_stays AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id,
    ie.intime,
    ie.outtime,
    ie.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
    ON ie.hadm_id = adm.hadm_id
  WHERE 
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM ie.intime) - (p.anchor_year - p.anchor_age)) BETWEEN 70 AND 80
    AND ie.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '428%') 
        OR (icd_version = 10 AND icd_code LIKE 'I50%')
    )
),
all_stays AS (
  SELECT 
    stay_id,
    subject_id,
    hadm_id,
    intime,
    outtime,
    los,
    1 AS group_flag
  FROM hf_cohort_stays
  UNION ALL
  SELECT 
    stay_id,
    subject_id,
    hadm_id,
    intime,
    outtime,
    los,
    2 AS group_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
stay_lab_counts AS (
  SELECT 
    s.stay_id,
    s.group_flag,
    COUNT(DISTINCT le.itemid) AS num_lab_tests
  FROM all_stays s
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON s.subject_id = le.subject_id
    AND s.hadm_id = le.hadm_id
    AND le.charttime >= s.intime
    AND le.charttime < DATETIME_ADD(s.intime, INTERVAL 72 HOUR)
    AND le.charttime <= s.outtime
  GROUP BY s.stay_id, s.group_flag
),
di_stats AS (
  SELECT 
    group_flag,
    AVG(num_lab_tests) AS di_mean,
    APPROX_QUANTILES(num_lab_tests, 100)[OFFSET(50)] AS di_median,
    APPROX_QUANTILES(num_lab_tests, 100)[OFFSET(75)] AS di_75th,
    APPROX_QUANTILES(num_lab_tests, 100)[OFFSET(95)] AS di_95th
  FROM stay_lab_counts
  GROUP BY group_flag
),
los_stats AS (
  SELECT 
    group_flag,
    AVG(los) AS mean_icu_los
  FROM all_stays
  GROUP BY group_flag
),
group_admissions AS (
  SELECT 
    hadm_id,
    1 AS group_flag
  FROM hf_cohort_stays
  GROUP BY hadm_id
  UNION ALL
  SELECT 
    hadm_id,
    2 AS group_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
mortality_stats AS (
  SELECT 
    ga.group_flag,
    AVG(adm.hospital_expire_flag) AS hospital_mortality
  FROM group_admissions ga
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ga.hadm_id = adm.hadm_id
  GROUP BY ga.group_flag
)
SELECT 
  CASE 
    WHEN di_stats.group_flag = 1 THEN 'Heart Failure Cohort' 
    WHEN di_stats.group_flag = 2 THEN 'General ICU Population' 
  END AS cohort,
  di_stats.di_mean,
  di_stats.di_median,
  di_stats.di_75th,
  di_stats.di_95th,
  los_stats.mean_icu_los,
  mortality_stats.hospital_mortality
FROM di_stats
INNER JOIN los_stats 
  ON di_stats.group_flag = los_stats.group_flag
INNER JOIN mortality_stats 
  ON di_stats.group_flag = mortality_stats.group_flag
ORDER BY di_stats.group_flag;