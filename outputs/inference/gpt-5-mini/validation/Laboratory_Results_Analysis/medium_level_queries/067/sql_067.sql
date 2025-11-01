WITH ami_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
    AND (
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
      OR (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (LOWER(COALESCE(dd.long_title, '')) LIKE '%acute myocardial infarction%')
    )
),

-- Get the first Troponin T measurement (by charttime) per admission
troponin_first AS (
  SELECT
    le.hadm_id,
    le.valuenum AS first_troponin,
    COALESCE(le.valueuom, '') AS first_troponin_uom,
    le.charttime AS first_troponin_time
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE le.valuenum IS NOT NULL
    AND (
      LOWER(li.label) LIKE '%troponin t%'
      OR LOWER(li.label) LIKE '%troponin-t%'
    )
  QUALIFY ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC, le.labevent_id ASC) = 1
),

-- Join AMI admissions to their first troponin and compute LOS in days
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    tf.first_troponin,
    tf.first_troponin_time,
    CASE
      WHEN a.admittime IS NOT NULL AND a.dischtime IS NOT NULL
      THEN TIMESTAMP_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0
      ELSE NULL
    END AS los_days
  FROM ami_admissions a
  JOIN troponin_first tf
    ON a.hadm_id = tf.hadm_id
  WHERE tf.first_troponin > 0.01
)

SELECT
  COUNT(DISTINCT hadm_id) AS admissions_count,
  COUNT(DISTINCT subject_id) AS patient_count,
  ROUND(AVG(anchor_age), 2) AS mean_age_years,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days,
  ROUND(AVG(first_troponin), 4) AS mean_first_troponin_ng_per_ml,
  APPROX_QUANTILES(first_troponin, 100)[OFFSET(50)] AS median_first_troponin_ng_per_ml,
  ROUND(STDDEV_POP(first_troponin), 4) AS sd_first_troponin_ng_per_ml,
  MIN(first_troponin) AS min_first_troponin_ng_per_ml,
  MAX(first_troponin) AS max_first_troponin_ng_per_ml,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS inhospital_deaths,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(hadm_id), 2) AS inhospital_mortality_percent
FROM cohort;