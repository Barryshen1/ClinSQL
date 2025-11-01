WITH target_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 37 AND 47
),
lab_events AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.itemid,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    CASE
      WHEN le.valuenum IS NOT NULL
        AND le.ref_range_lower IS NOT NULL
        AND le.ref_range_upper IS NOT NULL
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
      THEN 1
      ELSE 0
    END AS is_abnormal
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    target_admissions ta
  ON
    le.subject_id = ta.subject_id
    AND le.hadm_id = ta.hadm_id
  WHERE
    le.charttime BETWEEN ta.admittime AND ta.admittime + INTERVAL 72 HOUR
),
patient_lab_abnormal AS (
  SELECT
    ta.subject_id,
    ta.hadm_id,
    COUNT(DISTINCT CASE WHEN le.is_abnormal = 1 THEN le.itemid END) AS num_abnormal_labs
  FROM
    target_admissions ta
  LEFT JOIN
    lab_events le
  ON
    ta.subject_id = le.subject_id
    AND ta.hadm_id = le.hadm_id
  GROUP BY
    ta.subject_id, ta.hadm_id
),
all_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
),
all_lab_events AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.itemid,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    CASE
      WHEN le.valuenum IS NOT NULL
        AND le.ref_range_lower IS NOT NULL
        AND le.ref_range_upper IS NOT NULL
        AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
      THEN 1
      ELSE 0
    END AS is_abnormal
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN
    all_admissions aa
  ON
    le.subject_id = aa.subject_id
    AND le.hadm_id = aa.hadm_id
  WHERE
    le.charttime BETWEEN aa.admittime AND aa.admittime + INTERVAL 72 HOUR
),
all_patient_lab_abnormal AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    COUNT(DISTINCT CASE WHEN le.is_abnormal = 1 THEN le.itemid END) AS num_abnormal_labs
  FROM
    all_admissions aa
  LEFT JOIN
    all_lab_events le
  ON
    aa.subject_id = le.subject_id
    AND aa.hadm_id = le.hadm_id
  GROUP BY
    aa.subject_id, aa.hadm_id
)
SELECT
  (SELECT MAX(num_abnormal_labs) FROM patient_lab_abnormal) AS max_lab_score,
  (SELECT SUM(CASE WHEN num_abnormal_labs > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) FROM patient_lab_abnormal) AS target_critical_rate,
  (SELECT SUM(CASE WHEN num_abnormal_labs > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) FROM all_patient_lab_abnormal) AS general_critical_rate,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM
  target_admissions;