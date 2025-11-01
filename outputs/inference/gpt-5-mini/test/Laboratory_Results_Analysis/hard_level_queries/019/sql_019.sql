WITH
-- 1) AP cohort: admissions for male patients age 63-73 with acute pancreatitis diagnosis
ap_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND LOWER(dd.long_title) LIKE '%acute pancreat%'
),

-- 2) All lab events in first 72 hours for AP cohort, mark abnormal/critical using flag or ref ranges
ap_labs_72h AS (
  SELECT
    a.hadm_id,
    le.itemid,
    le.labevent_id,
    le.charttime,
    le.valuenum,
    le.value,
    le.flag,
    le.ref_range_lower,
    le.ref_range_upper,
    CASE
      WHEN le.flag IS NOT NULL AND TRIM(le.flag) != '' THEN 1
      WHEN le.valuenum IS NOT NULL
           AND (
                (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
                OR
                (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
               )
      THEN 1
      ELSE 0
    END AS is_critical
  FROM
    ap_admissions a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
),

-- 3) Per-admission instability score = number of distinct lab types with >=1 critical result in 72h
ap_instability_score AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT CASE WHEN is_critical = 1 THEN itemid ELSE NULL END) AS instability_score
  FROM ap_labs_72h
  GROUP BY hadm_id
),

-- 4) Get the P90 (approximate) of the instability score across the AP cohort
p90_val AS (
  SELECT
    (APPROX_QUANTILES(instability_score, 100))[OFFSET(90)] AS p90_score
  FROM ap_instability_score
),

-- 5) Identify AP admissions with score >= P90
ap_p90_admissions AS (
  SELECT
    s.hadm_id,
    s.instability_score
  FROM
    ap_instability_score s,
    p90_val
  WHERE
    p90_val.p90_score IS NOT NULL
    AND s.instability_score >= p90_val.p90_score
),

-- 6) Outcomes for AP P90 group
p90_outcomes AS (
  SELECT
    COUNT(DISTINCT a.hadm_id) AS p90_n_admissions,
    AVG(CASE WHEN a.hospital_expire_flag IS NOT NULL THEN a.hospital_expire_flag ELSE 0 END) AS p90_mortality_rate,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0) AS p90_mean_los_days
  FROM
    ap_admissions a
    JOIN ap_p90_admissions p90
      ON a.hadm_id = p90.hadm_id
),

-- 7) Per-lab critical rates for P90 AP group: use ap_labs_72h (already has is_critical)
p90_lab_rates AS (
  SELECT
    l.itemid,
    SUM(CASE WHEN l.is_critical = 1 THEN 1 ELSE 0 END) AS p90_critical_count,
    COUNT(1) AS p90_total_count,
    SAFE_DIVIDE(SUM(CASE WHEN l.is_critical = 1 THEN 1 ELSE 0 END), COUNT(1)) AS p90_critical_rate
  FROM
    ap_labs_72h l
    JOIN ap_p90_admissions p90
      ON l.hadm_id = p90.hadm_id
  GROUP BY l.itemid
),

-- 8) General inpatients: all admissions (no diagnosis restriction) and their 72h lab events; compute per-lab critical rates
general_lab_rates AS (
  SELECT
    le.itemid,
    COUNTIF(
      (le.flag IS NOT NULL AND TRIM(le.flag) != '')
      OR
      (
        le.valuenum IS NOT NULL
        AND (
          (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
          OR
          (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
        )
      )
    ) AS general_critical_count,
    COUNT(1) AS general_total_count,
    SAFE_DIVIDE(
      COUNTIF(
        (le.flag IS NOT NULL AND TRIM(le.flag) != '')
        OR
        (
          le.valuenum IS NOT NULL
          AND (
            (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
            OR
            (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
          )
        )
      ),
      COUNT(1)
    ) AS general_critical_rate
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a_all
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a_all.hadm_id = le.hadm_id
      AND le.charttime BETWEEN a_all.admittime AND TIMESTAMP_ADD(a_all.admittime, INTERVAL 72 HOUR)
  GROUP BY le.itemid
),

-- 9) Labels for labs (join to d_labitems)
lab_labels AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
)

-- Final select: return summary (P90, counts, outcomes) and per-lab comparisons
SELECT
  (SELECT p90_score FROM p90_val) AS ap_cohort_instability_p90,
  (SELECT COUNT(DISTINCT hadm_id) FROM ap_instability_score) AS ap_cohort_n_admissions,
  (SELECT p90_n_admissions FROM p90_outcomes) AS p90_group_n_admissions,
  (SELECT p90_mortality_rate FROM p90_outcomes) AS p90_group_mortality_rate,
  (SELECT p90_mean_los_days FROM p90_outcomes) AS p90_group_mean_los_days,
  lr.itemid,
  IFNULL(lb.label, 'UNKNOWN') AS lab_label,
  lr.p90_critical_count,
  lr.p90_total_count,
  lr.p90_critical_rate,
  gr.general_critical_count,
  gr.general_total_count,
  gr.general_critical_rate,
  SAFE_SUBTRACT(lr.p90_critical_rate, gr.general_critical_rate) AS rate_difference
FROM
  p90_lab_rates lr
  LEFT JOIN general_lab_rates gr
    ON lr.itemid = gr.itemid
  LEFT JOIN lab_labels lb
    ON lr.itemid = lb.itemid
ORDER BY
  rate_difference DESC,
  lr.p90_total_count DESC;