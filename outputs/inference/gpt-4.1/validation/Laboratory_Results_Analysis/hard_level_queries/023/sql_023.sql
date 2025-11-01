WITH
-- 1. Identify AMI admissions in 90–100-year-old females
ami_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON adm.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` didx
      ON dx.icd_code = didx.icd_code AND dx.icd_version = didx.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '410%') -- ICD-9 AMI
      OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%')) -- ICD-10 AMI
    )
),

-- 2. Compute lab-instability score for each AMI admission (first 48h)
ami_lab_scores AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.anchor_age,
    a.gender,
    COUNTIF(
      (le.flag = 'abnormal')
      OR (le.flag = 'critical')
      OR (
        le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
    ) AS lab_instability_score,
    COUNTIF(le.flag = 'critical') AS critical_lab_count,
    COUNT(le.labevent_id) AS total_lab_count
  FROM
    ami_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.hadm_id = le.hadm_id
      AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.anchor_age, a.gender
),

-- 3. Calculate 75th percentile of lab-instability score
ami_p75 AS (
  SELECT
    APPROX_QUANTILES(lab_instability_score, 4)[OFFSET(3)] AS p75_lab_instability
  FROM
    ami_lab_scores
),

-- 4. Select AMI admissions with lab-instability score >= P75
ami_high_instability AS (
  SELECT
    als.*,
    SAFE_DIVIDE(critical_lab_count, total_lab_count) AS critical_lab_rate,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0 AS los_days
  FROM
    ami_lab_scores als
    CROSS JOIN ami_p75
  WHERE
    als.lab_instability_score >= ami_p75.p75_lab_instability
),

-- 5. All inpatients aged 90–100 (for comparison)
all_inpatients AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
  WHERE
    pat.anchor_age BETWEEN 90 AND 100
),

all_inpatients_lab AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.anchor_age,
    a.gender,
    COUNTIF(le.flag = 'critical') AS critical_lab_count,
    COUNT(le.labevent_id) AS total_lab_count,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24.0 AS los_days
  FROM
    all_inpatients a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.hadm_id = le.hadm_id
      AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag, a.anchor_age, a.gender
)

-- 6. Final output: summary stats for both groups
SELECT
  'AMI Female Admissions 90-100, Lab Instability >= P75' AS cohort,
  COUNT(*) AS n_admissions,
  SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) AS mortality_rate,
  AVG(los_days) AS mean_los_days,
  AVG(SAFE_DIVIDE(critical_lab_count, NULLIF(total_lab_count,0))) AS mean_critical_lab_rate
FROM
  ami_high_instability

UNION ALL

SELECT
  'All Inpatients 90-100' AS cohort,
  COUNT(*) AS n_admissions,
  SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) AS mortality_rate,
  AVG(los_days) AS mean_los_days,
  AVG(SAFE_DIVIDE(critical_lab_count, NULLIF(total_lab_count,0))) AS mean_critical_lab_rate
FROM
  all_inpatients_lab;