WITH patient_admissions AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 90 AND 100
),

ami_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (
    SUBSTR(icd_code, 1, 3) = 'I21' OR
    SUBSTR(icd_code, 1, 3) = 'I22'
  )
  AND icd_version = 10
),

ami_admissions AS (
  SELECT pa.*
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN ami_codes ac
    ON di.icd_code = ac.icd_code AND di.icd_version = 10
),

lab_abnormalities AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN ami_admissions aa
    ON le.hadm_id = aa.hadm_id
  WHERE le.charttime >= aa.admittime
    AND le.charttime <= DATETIME_ADD(aa.admittime, INTERVAL 48 HOUR)
    AND le.valuenum IS NOT NULL
    AND (LOWER(le.flag) = 'abnormal' OR LOWER(le.flag) = 'abn')
  GROUP BY le.hadm_id
),

percentile_threshold AS (
  SELECT
    APPROX_QUANTILES(abnormal_lab_count, 1000)[OFFSET(750)] AS p75_score
  FROM lab_abnormalities
),

ami_with_instability AS (
  SELECT
    aa.*,
    COALESCE(lab.abnormal_lab_count, 0) AS lab_instability_score
  FROM ami_admissions aa
  LEFT JOIN lab_abnormalities lab
    ON aa.hadm_id = lab.hadm_id
),

p75_ami AS (
  SELECT *
  FROM ami_with_instability, percentile_threshold
  WHERE lab_instability_score >= p75_score
),

summary_p75 AS (
  SELECT
    'AMI >=P75' AS group_label,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / (24 * 3600)) AS mean_los_days,
    AVG(lab_instability_score) AS mean_critical_lab_rate
  FROM p75_ami
),

all_elderly_females AS (
  SELECT
    'All 90-100F' AS group_label,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / (24 * 3600)) AS mean_los_days,
    COALESCE(AVG(lab.abnormal_lab_count), 0) AS mean_critical_lab_rate
  FROM patient_admissions
  LEFT JOIN (
    SELECT
      le.hadm_id,
      COUNT(*) AS abnormal_lab_count
    FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
    INNER JOIN patient_admissions pa
      ON le.hadm_id = pa.hadm_id
    WHERE le.charttime >= pa.admittime
      AND le.charttime <= DATETIME_ADD(pa.admittime, INTERVAL 48 HOUR)
      AND le.valuenum IS NOT NULL
      AND (LOWER(le.flag) = 'abnormal' OR LOWER(le.flag) = 'abn')
    GROUP BY le.hadm_id
  ) lab ON patient_admissions.hadm_id = lab.hadm_id
)

SELECT
  group_label,
  ROUND(mortality_rate, 3) AS mortality_rate,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(mean_critical_lab_rate, 2) AS mean_critical_lab_rate
FROM summary_p75

UNION ALL

SELECT
  group_label,
  ROUND(mortality_rate, 3) AS mortality_rate,
  ROUND(mean_los_days, 2) AS mean_los_days,
  ROUND(mean_critical_lab_rate, 2) AS mean_critical_lab_rate
FROM all_elderly_females

ORDER BY group_label;