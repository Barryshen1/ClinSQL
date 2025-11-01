WITH cohort_stays AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.subject_id = adm.subject_id
     AND icu.hadm_id    = adm.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON icu.subject_id = d.subject_id
     AND icu.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
     AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(dd.long_title) LIKE '%acute respiratory failure%'
),
vital_itemids AS (
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) IN ('mean arterial pressure', 'heart rate')
),
vitals AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    i.label,
    v.valuenum,
    v.charttime
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` v
    JOIN vital_itemids i
      ON v.itemid = i.itemid
),
vitals_48h AS (
  SELECT
    c.stay_id,
    v.label,
    v.valuenum
  FROM
    cohort_stays c
    JOIN vitals v
      ON c.subject_id = v.subject_id
     AND c.hadm_id    = v.hadm_id
     AND c.stay_id    = v.stay_id
     AND v.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
),
per_stay_metrics AS (
  SELECT
    stay_id,
    COUNT(*) AS total_meas,
    SUM(CASE WHEN label = 'mean arterial pressure' AND valuenum < 65 THEN 1 ELSE 0 END) AS map_eps,
    SUM(CASE WHEN label = 'heart rate' AND valuenum > 100 THEN 1 ELSE 0 END) AS tach_eps
  FROM
    vitals_48h
  GROUP BY
    stay_id
),
stay_with_index AS (
  SELECT
    m.stay_id,
    m.map_eps,
    m.tach_eps,
    m.total_meas,
    SAFE_DIVIDE(m.map_eps + m.tach_eps, m.total_meas) AS vii
  FROM
    per_stay_metrics m
),
cohort_metrics AS (
  SELECT
    c.stay_id,
    c.los,
    c.hospital_expire_flag AS death,
    s.map_eps,
    s.tach_eps,
    s.vii
  FROM
    cohort_stays c
    JOIN stay_with_index s USING (stay_id)
),
percentiles AS (
  SELECT
    APPROX_QUANTILES(vii, 100)[OFFSET(94)] AS p95_vii,
    APPROX_QUANTILES(vii, 100)[OFFSET(74)] AS p75_vii
  FROM
    cohort_metrics
),
top_quartile AS (
  SELECT
    cm.*
  FROM
    cohort_metrics cm
    CROSS JOIN percentiles p
  WHERE
    cm.vii >= p.p75_vii
),
grouped_metrics AS (
  SELECT
    'Top quartile cohort' AS group_label,
    AVG(map_eps)       AS avg_map_eps,
    AVG(tach_eps)      AS avg_tach_eps,
    AVG(los)           AS avg_los,
    AVG(death)         AS mortality_rate
  FROM
    top_quartile

  UNION ALL

  SELECT
    'All ICU stays' AS group_label,
    AVG(s.map_eps)       AS avg_map_eps,
    AVG(s.tach_eps)      AS avg_tach_eps,
    AVG(c.los)           AS avg_los,
    AVG(adm.hospital_expire_flag) AS mortality_rate
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` c
    JOIN stay_with_index s USING (stay_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON c.subject_id = adm.subject_id
     AND c.hadm_id    = adm.hadm_id
)

SELECT
  p.p95_vii,
  gm.*
FROM
  percentiles p
  CROSS JOIN grouped_metrics gm
ORDER BY
  gm.group_label;