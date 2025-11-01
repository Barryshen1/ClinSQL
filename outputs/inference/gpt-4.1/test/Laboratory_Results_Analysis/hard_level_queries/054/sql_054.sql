WITH female_38_48 AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),

ami_admissions AS (
  SELECT DISTINCT
    f.subject_id,
    f.hadm_id,
    f.anchor_age,
    f.gender,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag
  FROM
    female_38_48 f
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON f.hadm_id = d.hadm_id
  WHERE
    (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^410'))
      OR
      (d.icd_version = 10 AND (REGEXP_CONTAINS(d.icd_code, r'^I21') OR REGEXP_CONTAINS(d.icd_code, r'^I22')))
    )
),

control_admissions AS (
  SELECT
    f.subject_id,
    f.hadm_id,
    f.anchor_age,
    f.gender,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag
  FROM
    female_38_48 f
  WHERE
    f.hadm_id NOT IN (SELECT hadm_id FROM ami_admissions)
),

-- Step 2: Calculate lab instability score for each admission (first 72h)
lab_instability AS (
  SELECT
    l.hadm_id,
    COUNT(DISTINCT l.labevent_id) AS instability_score
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON l.hadm_id = a.hadm_id
  WHERE
    l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND (
      l.flag = 'abnormal'
      OR (
        l.valuenum IS NOT NULL
        AND (
          (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
          OR
          (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
        )
      )
    )
  GROUP BY
    l.hadm_id
),

-- Step 3: Merge instability scores with AMI and controls
ami_with_score AS (
  SELECT
    a.*,
    COALESCE(l.instability_score, 0) AS instability_score
  FROM
    ami_admissions a
    LEFT JOIN lab_instability l
      ON a.hadm_id = l.hadm_id
),

controls_with_score AS (
  SELECT
    c.*,
    COALESCE(l.instability_score, 0) AS instability_score
  FROM
    control_admissions c
    LEFT JOIN lab_instability l
      ON c.hadm_id = l.hadm_id
),

-- Step 4: Compute quartiles for AMI instability scores
ami_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS instability_quartile
  FROM
    ami_with_score
),

-- Step 5: Aggregate outcomes by quartile
quartile_outcomes AS (
  SELECT
    instability_quartile,
    COUNT(*) AS n_ami_admissions,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS avg_los_days,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_rate,
    AVG(instability_score) AS avg_instability_score
  FROM
    ami_quartiles
  GROUP BY
    instability_quartile
  ORDER BY
    instability_quartile
),

-- Step 6: Overall critical-lab rates for AMI and controls
overall_rates AS (
  SELECT
    'AMI' AS group_type,
    COUNT(*) AS n_admissions,
    SUM(instability_score) AS total_critical_labs,
    AVG(instability_score) AS avg_critical_labs_per_admission
  FROM
    ami_with_score
  UNION ALL
  SELECT
    'Control' AS group_type,
    COUNT(*) AS n_admissions,
    SUM(instability_score) AS total_critical_labs,
    AVG(instability_score) AS avg_critical_labs_per_admission
  FROM
    controls_with_score
)

-- Final output: Part 1 (quartile outcomes), Part 2 (overall rates)
SELECT
  'AMI Quartiles' AS section,
  CAST(instability_quartile AS STRING) AS quartile,
  n_ami_admissions,
  ROUND(avg_los_days,2) AS avg_los_days,
  deaths,
  ROUND(mortality_rate*100,2) AS mortality_rate_percent,
  ROUND(avg_instability_score,2) AS avg_instability_score
FROM
  quartile_outcomes

UNION ALL

SELECT
  'Critical Lab Rates' AS section,
  group_type AS quartile,
  n_admissions,
  NULL AS avg_los_days,
  NULL AS deaths,
  NULL AS mortality_rate_percent,
  ROUND(avg_critical_labs_per_admission,2) AS avg_instability_score
FROM
  overall_rates
ORDER BY
  section, quartile
;