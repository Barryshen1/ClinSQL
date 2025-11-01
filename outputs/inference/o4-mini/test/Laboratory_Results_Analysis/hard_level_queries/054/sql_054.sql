WITH ami_adm AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND (d.icd_code LIKE '410%' AND d.icd_version = 9)
),
labs_ami AS (
  SELECT
    la.subject_id,
    la.hadm_id,
    COUNTIF(la.valuenum < la.ref_range_lower OR la.valuenum > la.ref_range_upper) AS abnormal_count
  FROM
    ami_adm adm
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` la
      ON adm.subject_id = la.subject_id
      AND adm.hadm_id = la.hadm_id
      AND la.charttime BETWEEN adm.admittime AND TIMESTAMP_ADD(adm.admittime, INTERVAL 72 HOUR)
  WHERE
    la.valuenum IS NOT NULL
    AND la.ref_range_lower IS NOT NULL
    AND la.ref_range_upper IS NOT NULL
  GROUP BY
    la.subject_id,
    la.hadm_id
),
scores AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    COALESCE(lab.abnormal_count, 0) AS lab_instability_score,
    adm.los_days,
    adm.hospital_expire_flag
  FROM
    ami_adm adm
    LEFT JOIN labs_ami lab
      ON adm.hadm_id = lab.hadm_id
),
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY lab_instability_score) AS quartile
  FROM
    scores
),
ami_metrics AS (
  SELECT
    quartile,
    COUNT(*) AS n_admissions,
    AVG(los_days) AS avg_los_days,
    SUM(hospital_expire_flag) * 1.0 / COUNT(*) AS mortality_rate
  FROM
    quartiles
  GROUP BY
    quartile
  ORDER BY
    quartile
),
controls_adm AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND a.hadm_id NOT IN (
      SELECT DISTINCT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_version = 9
        AND icd_code LIKE '410%'
    )
),
labs_ctrl AS (
  SELECT
    ca.hadm_id,
    COUNT(*) AS total_labs,
    COUNTIF(la.valuenum < la.ref_range_lower OR la.valuenum > la.ref_range_upper) AS abnormal_labs
  FROM
    controls_adm ca
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` la
      ON ca.subject_id = la.subject_id
      AND ca.hadm_id = la.hadm_id
      AND la.charttime BETWEEN ca.admittime AND TIMESTAMP_ADD(ca.admittime, INTERVAL 72 HOUR)
  WHERE
    la.valuenum IS NOT NULL
    AND la.ref_range_lower IS NOT NULL
    AND la.ref_range_upper IS NOT NULL
  GROUP BY
    ca.hadm_id
),
ctrl_metrics AS (
  SELECT
    SUM(abnormal_labs) * 1.0 / SUM(total_labs) AS control_abnormal_rate
  FROM
    labs_ctrl
)
-- Final output: AMI quartile metrics plus control rate
SELECT
  'AMI Quartile Metrics' AS cohort,
  CAST(quartile AS STRING) AS group_label,
  n_admissions,
  ROUND(avg_los_days, 2) AS avg_los_days,
  ROUND(mortality_rate, 3) AS mortality_rate
FROM
  ami_metrics
UNION ALL
SELECT
  'Age‐matched Controls' AS cohort,
  'Overall' AS group_label,
  NULL AS n_admissions,
  NULL AS avg_los_days,
  ROUND(control_abnormal_rate, 3) AS mortality_rate
FROM
  ctrl_metrics;