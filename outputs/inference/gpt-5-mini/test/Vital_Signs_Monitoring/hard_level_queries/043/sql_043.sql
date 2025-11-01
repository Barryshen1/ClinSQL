WITH
-- 1) Identify admissions with respiratory failure via diagnosis text
resp_dx AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE LOWER(dd.long_title) LIKE '%respiratory failure%'
),

-- 2) ICU stays joined to patient & admission info, mark respiratory failure stays
icu_with_info AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los,
    p.gender,
    p.anchor_age,
    a.hospital_expire_flag,
    CASE WHEN r.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS resp_failure
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ic.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ic.hadm_id = a.hadm_id
  LEFT JOIN resp_dx r
    ON ic.hadm_id = r.hadm_id
),

-- 3) Map itemids to vital types via d_items label patterns (ICU d_items)
vital_itemids AS (
  SELECT
    itemid,
    label,
    CASE
      WHEN LOWER(label) LIKE '%mean arterial%' OR LOWER(label) LIKE '%arterial blood pressure mean%' OR LOWER(label) LIKE '%map%' THEN 'map'
      WHEN LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%hr %' OR LOWER(label) = 'hr' THEN 'hr'
      WHEN LOWER(label) LIKE '%respiratory rate%' OR LOWER(label) LIKE '%rr %' OR LOWER(label) = 'rr' THEN 'rr'
      WHEN LOWER(label) LIKE '%oxygen saturation%' OR LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 saturation%' THEN 'spo2'
      WHEN LOWER(label) LIKE '%temperature%' OR LOWER(label) LIKE '%temp%' THEN 'temp'
      ELSE NULL
    END AS vital_type
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial%' OR LOWER(label) LIKE '%arterial blood pressure mean%' OR LOWER(label) LIKE '%map%'
     OR LOWER(label) LIKE '%heart rate%' OR LOWER(label) LIKE '%hr %' OR LOWER(label) = 'hr'
     OR LOWER(label) LIKE '%respiratory rate%' OR LOWER(label) LIKE '%rr %' OR LOWER(label) = 'rr'
     OR LOWER(label) LIKE '%oxygen saturation%' OR LOWER(label) LIKE '%spo2%' OR LOWER(label) LIKE '%o2 saturation%'
     OR LOWER(label) LIKE '%temperature%' OR LOWER(label) LIKE '%temp%'
),

-- 4) All charted vital measurements in first 48h for icu stays that are respiratory failure (for population normalizers)
chartevents_48h_all_rf AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    vi.vital_type,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN vital_itemids vi
    ON ce.itemid = vi.itemid
  JOIN icu_with_info ic
    ON ce.stay_id = ic.stay_id
  WHERE ic.resp_failure = 1
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
),

-- 5) Population SD per vital type across all respiratory-failure ICU stays (used to normalize per-vital SD)
pop_sd_per_vital AS (
  SELECT
    vital_type,
    STDDEV_SAMP(valuenum) AS pop_sd
  FROM chartevents_48h_all_rf
  GROUP BY vital_type
),

-- 6) Per-stay, per-vital SD and counts within first 48h for all ICU stays (we'll later limit to cohorts)
per_stay_vital_stats AS (
  SELECT
    ce.stay_id,
    ce.vital_type,
    COUNT(*) AS n_measure,
    STDDEV_SAMP(ce.valuenum) AS sd_vital,
    AVG(ce.valuenum) AS mean_vital
  FROM (
    SELECT ce.*, vi.vital_type
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN vital_itemids vi
      ON ce.itemid = vi.itemid
    JOIN icu_with_info ic
      ON ce.stay_id = ic.stay_id
    WHERE ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
  ) ce
  GROUP BY ce.stay_id, ce.vital_type
),

-- 7) Compute normalized SDs and stay-level VII using pop SDs
per_stay_vii AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.hadm_id,
    s.intime,
    s.outtime,
    s.los,
    s.gender,
    s.anchor_age,
    s.hospital_expire_flag,
    s.resp_failure,
    ARRAY_AGG(STRUCT(
      ps.vital_type,
      ps.n_measure,
      ps.sd_vital,
      p.pop_sd,
      CASE WHEN p.pop_sd IS NULL OR p.pop_sd = 0 THEN NULL ELSE ps.sd_vital / p.pop_sd END AS normalized_sd
    )) AS vital_sd_array
  FROM icu_with_info s
  LEFT JOIN per_stay_vital_stats ps
    ON s.stay_id = ps.stay_id
  LEFT JOIN pop_sd_per_vital p
    ON ps.vital_type = p.vital_type
  GROUP BY s.stay_id, s.subject_id, s.hadm_id, s.intime, s.outtime, s.los, s.gender, s.anchor_age, s.hospital_expire_flag, s.resp_failure
),

-- 8) Flatten per_stay_vii to compute VII and per-stay burden metrics (MAP & HR burdens)
per_stay_metrics AS (
  SELECT
    psv.stay_id,
    psv.subject_id,
    psv.hadm_id,
    psv.intime,
    psv.outtime,
    psv.los,
    psv.gender,
    psv.anchor_age,
    psv.hospital_expire_flag,
    psv.resp_failure,
    (
      SELECT
        CASE
          WHEN COUNT(1) = 0 THEN NULL
          ELSE SQRT(SUM(POW(v.normalized_sd, 2)) / COUNT(1))
        END
      FROM UNNEST(psv.vital_sd_array) v
      WHERE v.normalized_sd IS NOT NULL
    ) AS vital_instability_index,
    (
      SELECT COUNT(1) FROM UNNEST(psv.vital_sd_array) v WHERE v.normalized_sd IS NOT NULL
    ) AS n_vitals_for_vii
  FROM per_stay_vii psv
),

-- 9) Compute per-stay MAP and HR burdens (proportion of MAP<65 and HR>100 in first 48h)
per_stay_burdens AS (
  SELECT
    m.stay_id,
    m.subject_id,
    m.hadm_id,
    m.vital_instability_index,
    m.n_vitals_for_vii,
    m.los,
    m.gender,
    m.anchor_age,
    m.hospital_expire_flag,
    m.resp_failure,
    -- MAP burden
    CASE WHEN map_ct.total_map_count = 0 THEN NULL ELSE SAFE_DIVIDE(map_ct.map_low_count, map_ct.total_map_count) END AS hypotensive_burden_map_lt65,
    map_ct.total_map_count,
    map_ct.map_low_count,
    -- HR burden
    CASE WHEN hr_ct.total_hr_count = 0 THEN NULL ELSE SAFE_DIVIDE(hr_ct.hr_high_count, hr_ct.total_hr_count) END AS tachy_burden_hr_gt100,
    hr_ct.total_hr_count,
    hr_ct.hr_high_count
  FROM per_stay_metrics m
  LEFT JOIN (
    SELECT
      ce.stay_id,
      COUNT(*) AS total_map_count,
      SUM(CASE WHEN ce.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN vital_itemids vi ON ce.itemid = vi.itemid AND vi.vital_type = 'map'
    JOIN icu_with_info ic ON ce.stay_id = ic.stay_id
    WHERE ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
    GROUP BY ce.stay_id
  ) map_ct ON m.stay_id = map_ct.stay_id
  LEFT JOIN (
    SELECT
      ce.stay_id,
      COUNT(*) AS total_hr_count,
      SUM(CASE WHEN ce.valuenum > 100 THEN 1 ELSE 0 END) AS hr_high_count
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    JOIN vital_itemids vi ON ce.itemid = vi.itemid AND vi.vital_type = 'hr'
    JOIN icu_with_info ic ON ce.stay_id = ic.stay_id
    WHERE ce.valuenum IS NOT NULL
      AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
    GROUP BY ce.stay_id
  ) hr_ct ON m.stay_id = hr_ct.stay_id
)

-- Final aggregation: compute cohort-level summaries for
--  A) male patients age 40-50 with resp failure
--  B) all resp-failure ICU stays
SELECT
  cohort,
  COUNT(1) AS n_stays_included,
  -- Vital Instability Index distribution: SD and percentiles
  STDDEV_SAMP(vital_instability_index) AS vii_sd_across_stays,
  (APPROX_QUANTILES(vital_instability_index, 100))[OFFSET(25)] AS vii_p25,
  (APPROX_QUANTILES(vital_instability_index, 100))[OFFSET(50)] AS vii_p50,
  (APPROX_QUANTILES(vital_instability_index, 100))[OFFSET(75)] AS vii_p75,
  (APPROX_QUANTILES(vital_instability_index, 100))[OFFSET(95)] AS vii_p95,
  -- Burdens: mean of per-stay burdens (only among stays that had at least one respective measurement)
  AVG(hypotensive_burden_map_lt65) AS mean_hypotensive_burden_map_lt65,
  AVG(tachy_burden_hr_gt100) AS mean_tachy_burden_hr_gt100,
  -- ICU LOS stats
  AVG(los) AS mean_icu_los_days,
  (APPROX_QUANTILES(los, 100))[OFFSET(50)] AS icu_los_median_days,
  (APPROX_QUANTILES(los, 100))[OFFSET(25)] AS icu_los_p25_days,
  (APPROX_QUANTILES(los, 100))[OFFSET(75)] AS icu_los_p75_days,
  -- Hospital mortality rate (hospital_expire_flag = 1)
  SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(1)) AS hospital_mortality_rate
FROM (
  SELECT
    CASE
      WHEN resp_failure = 1 AND gender = 'M' AND anchor_age BETWEEN 40 AND 50 THEN 'male_40_50_resp_failure'
      WHEN resp_failure = 1 THEN 'all_resp_failure'
      ELSE NULL
    END AS cohort,
    vital_instability_index,
    hypotensive_burden_map_lt65,
    tachy_burden_hr_gt100,
    los,
    hospital_expire_flag,
    resp_failure
  FROM per_stay_burdens
  WHERE resp_failure = 1
)
WHERE cohort IS NOT NULL
GROUP BY cohort
ORDER BY cohort;