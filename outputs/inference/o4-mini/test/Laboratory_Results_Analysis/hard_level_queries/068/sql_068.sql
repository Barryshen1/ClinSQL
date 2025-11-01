WITH
-- 1. Define base admissions of interest (female, age 89-99)
base_adm AS (
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
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
),
-- 2. Septic shock cohort
septic_adm AS (
  SELECT DISTINCT
    b.*
  FROM
    base_adm b
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON b.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%septic shock%'
),
-- 3. ICU stays for septic cohort
septic_icu AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime
  FROM
    septic_adm sa
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` s
      ON sa.hadm_id = s.hadm_id
),
-- 4. Compute instability score = stddev of vital signs in first 48h
vital_ids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN (
    'heart rate', 'respiratory rate',
    'temperature c', 'systolic blood pressure',
    'diastolic blood pressure'
  )
),
instability AS (
  SELECT
    si.stay_id,
    STDDEV_POP(c.valuenum) AS instability_score
  FROM
    septic_icu si
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
      ON si.stay_id = c.stay_id
    JOIN vital_ids v
      ON c.itemid = v.itemid
  WHERE
    c.valuenum IS NOT NULL
    AND c.charttime BETWEEN si.intime
      AND TIMESTAMP_ADD(si.intime, INTERVAL 48 HOUR)
  GROUP BY
    si.stay_id
),
-- 5. Cohort instability percentiles
instability_stats AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.25) OVER() AS q1,
    PERCENTILE_CONT(instability_score, 0.50) OVER() AS median,
    PERCENTILE_CONT(instability_score, 0.75) OVER() AS q3
  FROM
    instability
  LIMIT 1
),
-- 6. Abnormal labs in first 48h for any admission
adm_labs AS (
  SELECT
    b.hadm_id,
    COUNTIF(
      le.valuenum IS NOT NULL
      AND (
        le.valuenum < le.ref_range_lower
        OR le.valuenum > le.ref_range_upper
      )
    ) > 0 AS has_abn_lab
  FROM
    base_adm b
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON b.hadm_id = le.hadm_id
      AND le.valuenum IS NOT NULL
      AND le.charttime BETWEEN b.admittime
        AND TIMESTAMP_ADD(b.admittime, INTERVAL 48 HOUR)
  GROUP BY
    b.hadm_id
),
-- 7. Abnormal lab frequency: septic vs general
abn_freq AS (
  SELECT
    'SepticShock' AS group_label,
    COUNTIF(al.has_abn_lab) / COUNT(*) AS pct_abn_lab
  FROM
    septic_adm sa
    LEFT JOIN adm_labs al ON sa.hadm_id = al.hadm_id
  UNION ALL
  SELECT
    'GeneralFemale89_99' AS group_label,
    COUNTIF(al.has_abn_lab) / COUNT(*) AS pct_abn_lab
  FROM
    base_adm ba
    LEFT JOIN adm_labs al ON ba.hadm_id = al.hadm_id
),
-- 8. Cohort LOS and mortality
cohort_outcomes AS (
  SELECT
    AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    septic_adm
)
-- 9. Final select combining everything
SELECT
  inst.q1 AS instability_q1,
  inst.median AS instability_median,
  inst.q3 AS instability_q3,
  (inst.q3 - inst.q1) AS instability_iqr,
  af.group_label,
  af.pct_abn_lab,
  co.avg_los_days,
  co.mortality_rate
FROM
  instability_stats AS inst
  CROSS JOIN cohort_outcomes AS co
  CROSS JOIN abn_freq AS af;