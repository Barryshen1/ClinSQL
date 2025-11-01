WITH base AS (
  -- Identify eligible male inpatients aged 54-64 with heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 54 AND 64
    -- heart failure diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
instability AS (
  -- Per-admission instability score (std dev of lab values within first 48h)
  SELECT
    b.subject_id,
    b.hadm_id,
    IFNULL(STDDEV_SAMP(lv.valuenum), 0) AS instability_score,
    COUNT(lv.valuenum) AS labs_in_window,
    SUM(CASE WHEN LOWER(lv.flag) LIKE '%critical%' THEN 1 ELSE 0 END) AS critical_labs
  FROM base AS b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS lv
    ON lv.subject_id = b.subject_id
   AND lv.hadm_id = b.hadm_id
   AND lv.charttime BETWEEN b.admittime AND TIMESTAMP_ADD(b.admittime, INTERVAL 48 HOUR)
   AND lv.valuenum IS NOT NULL
  GROUP BY b.subject_id, b.hadm_id
),
instability_with_rate AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.instability_score,
    i.labs_in_window,
    i.critical_labs,
    CASE
      WHEN i.labs_in_window > 0 THEN SAFE_DIVIDE(i.critical_labs, i.labs_in_window)
      ELSE 0
    END AS critical_rate
  FROM instability AS i
),
threshold AS (
  -- 95th percentile threshold of instability_score across eligible admissions
  SELECT quantiles[OFFSET(94)] AS threshold_95
  FROM (
    SELECT APPROX_QUANTILES(instability_score, 100) AS quantiles
    FROM instability_with_rate
  )
),
final AS (
  -- Attach admissions times and categorize into High instability vs Controls
  SELECT
    CASE
      WHEN i.instability_score >= t.threshold_95 THEN 'High instability (>=95th)'
      ELSE 'Controls'
    END AS group_label,
    i.subject_id,
    i.hadm_id,
    b.admittime AS admittime,
    b.dischtime AS dischtime,
    b.hospital_expire_flag AS hospital_expire_flag,
    i.instability_score,
    i.critical_rate
  FROM instability_with_rate AS i
  JOIN base AS b
    ON b.subject_id = i.subject_id
   AND b.hadm_id = i.hadm_id
  CROSS JOIN threshold AS t
)
SELECT
  group_label,
  COUNT(*) AS n_patients,
  AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS in_hospital_mortality_rate,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 3600.0) AS mean_los_hours,
  AVG(critical_rate) AS mean_critical_lab_rate
FROM final
GROUP BY group_label
ORDER BY group_label;