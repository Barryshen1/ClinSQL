WITH critical_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE category IN ('Electrolytes', 'Renal', 'Hematology', 'Blood Gas', 'Cardiac')
),
base_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
),
cardiac_arrest_admissions AS (
  SELECT DISTINCT hadm_id
  FROM base_admissions b
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON b.hadm_id = d.hadm_id
  WHERE d.icd_code = 'I46.9'
    AND d.icd_version = 10
),
admission_labs AS (
  SELECT
    b.hadm_id,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper
  FROM base_admissions b
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON b.hadm_id = le.hadm_id
  JOIN critical_itemids c
    ON le.itemid = c.itemid
  WHERE le.charttime BETWEEN b.admittime
    AND TIMESTAMP_ADD(b.admittime, INTERVAL 48 HOUR)
),
abnormal_labs AS (
  SELECT
    hadm_id,
    CASE
      WHEN ref_range_lower IS NOT NULL AND ref_range_upper IS NOT NULL
        THEN CASE
          WHEN valuenum < ref_range_lower OR valuenum > ref_range_upper THEN 1
          ELSE 0
        END
      ELSE 0
    END AS is_abnormal
  FROM admission_labs
),
instability_scores AS (
  SELECT
    hadm_id,
    SUM(is_abnormal) AS instability_score
  FROM abnormal_labs
  GROUP BY hadm_id
),
admissions_with_score AS (
  SELECT
    b.hadm_id,
    b.hospital_expire_flag,
    b.dischtime,
    b.admittime,
    COALESCE(i.instability_score, 0) AS instability_score,
    CASE WHEN c.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_cardiac_arrest
  FROM base_admissions b
  LEFT JOIN instability_scores i
    ON b.hadm_id = i.hadm_id
  LEFT JOIN cardiac_arrest_admissions c
    ON b.hadm_id = c.hadm_id
),
cardiac_arrest_scores AS (
  SELECT instability_score
  FROM admissions_with_score
  WHERE is_cardiac_arrest = 1
),
p90 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90
  FROM cardiac_arrest_scores
),
high_risk_group AS (
  SELECT
    hadm_id,
    hospital_expire_flag,
    dischtime,
    admittime,
    instability_score
  FROM admissions_with_score
  WHERE is_cardiac_arrest = 1
    AND instability_score >= (SELECT p90 FROM p90)
),
group1_metrics AS (
  SELECT
    COUNT(*) AS count,
    AVG(hospital_expire_flag) * 100 AS mortality_percent,
    AVG(DATEDIFF(dischtime, admittime)) AS mean_los_days
  FROM high_risk_group
),
avg_instability_group1 AS (
  SELECT
    AVG(instability_score) AS avg_instability
  FROM high_risk_group
),
avg_instability_all AS (
  SELECT
    AVG(instability_score) AS avg_instability
  FROM admissions_with_score
  WHERE is_cardiac_arrest = 0
)
SELECT
  group1_metrics.*,
  (SELECT avg_instability FROM avg_instability_group1) AS avg_instability_group1,
  (SELECT avg_instability FROM avg_instability_all) AS avg_instability_all
FROM group1_metrics;