WITH
-- female patients in age window
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 63 AND 73
),

-- admissions that have a diagnosis containing "status epilepticus" in the diagnosis text
se_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code
    AND IFNULL(d.icd_version, 0) = IFNULL(dd.icd_version, 0)
  WHERE LOWER(dd.long_title) LIKE '%status epilepticus%'
),

-- ICU stays for eligible patients
eligible_icustays AS (
  SELECT ic.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN eligible_patients p USING (subject_id)
),

-- mark which icu stays belong to SE admissions
icustays_labeled AS (
  SELECT ic.*,
         CASE WHEN sa.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_se_admission
  FROM eligible_icustays ic
  LEFT JOIN se_admissions sa
    ON ic.hadm_id = sa.hadm_id
),

-- Define a helper of vitals events in first 72 hours, flagging vital types and abnormalities
vitals_72h AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    -- window end is min(intime + 72h, outtime)
    LEAST(TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR), ic.outtime) AS window_end,
    ce.charttime,
    ce.itemid,
    di.label,
    ce.valuenum,

    -- identify vital types heuristic via d_items.label (lowercased)
    CASE
      WHEN LOWER(di.label) LIKE '%heart rate%' THEN 1 ELSE 0
    END AS is_hr,
    CASE
      WHEN LOWER(di.label) LIKE '%mean arterial%' OR LOWER(di.label) LIKE '%mean blood pressure%' OR LOWER(di.label) LIKE '%map%' THEN 1 ELSE 0
    END AS is_map,
    CASE
      WHEN LOWER(di.label) LIKE '%systolic%' OR LOWER(di.label) LIKE '%arterial bp systolic%' OR LOWER(di.label) LIKE '%non inv bp systolic%' OR LOWER(di.label) LIKE '%systolic blood pressure%' THEN 1 ELSE 0
    END AS is_sbp,
    CASE
      WHEN LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%resp rate%' OR LOWER(di.label) LIKE '%respiratory%' THEN 1 ELSE 0
    END AS is_rr,
    CASE
      WHEN LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%' OR LOWER(di.label) LIKE '%o2 sat%' OR LOWER(di.label) LIKE '%pulse ox%' THEN 1 ELSE 0
    END AS is_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN icustays_labeled ic
    ON ce.subject_id = ic.subject_id
    AND ce.hadm_id = ic.hadm_id
    AND ce.stay_id = ic.stay_id
  WHERE ce.charttime >= ic.intime
    AND ce.charttime <= LEAST(TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR), ic.outtime)
    -- limit to records that plausibly represent vitals by label pattern
    AND (
         LOWER(di.label) LIKE '%heart rate%'
      OR LOWER(di.label) LIKE '%mean arterial%'
      OR LOWER(di.label) LIKE '%mean blood pressure%'
      OR LOWER(di.label) LIKE '%map%'
      OR LOWER(di.label) LIKE '%systolic%'
      OR LOWER(di.label) LIKE '%respiratory rate%'
      OR LOWER(di.label) LIKE '%resp rate%'
      OR LOWER(di.label) LIKE '%spo2%'
      OR LOWER(di.label) LIKE '%oxygen saturation%'
      OR LOWER(di.label) LIKE '%pulse ox%'
    )
    AND ce.valuenum IS NOT NULL
),

-- Aggregate per stay: counts of measurements and abnormal events, and compute vital_instability_index
per_stay_metrics AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    MIN(v.intime) AS intime,
    MIN(v.window_end) AS window_end,
    -- measurement counts per vital-type
    SUM(CASE WHEN v.is_hr = 1 THEN 1 ELSE 0 END) AS hr_count,
    SUM(CASE WHEN v.is_hr = 1 AND v.valuenum > 100 THEN 1 ELSE 0 END) AS hr_tachy_count,
    SUM(CASE WHEN v.is_map = 1 THEN 1 ELSE 0 END) AS map_count,
    SUM(CASE WHEN v.is_map = 1 AND v.valuenum < 65 THEN 1 ELSE 0 END) AS map_low_count,
    SUM(CASE WHEN v.is_sbp = 1 THEN 1 ELSE 0 END) AS sbp_count,
    SUM(CASE WHEN v.is_sbp = 1 AND v.valuenum < 90 THEN 1 ELSE 0 END) AS sbp_low_count,
    SUM(CASE WHEN v.is_rr = 1 THEN 1 ELSE 0 END) AS rr_count,
    SUM(CASE WHEN v.is_rr = 1 AND v.valuenum > 25 THEN 1 ELSE 0 END) AS rr_high_count,
    SUM(CASE WHEN v.is_spo2 = 1 THEN 1 ELSE 0 END) AS spo2_count,
    SUM(CASE WHEN v.is_spo2 = 1 AND v.valuenum < 90 THEN 1 ELSE 0 END) AS spo2_low_count,
    -- total abnormal flag events across all vitals
    SUM(
      (CASE WHEN v.is_hr = 1 AND v.valuenum > 100 THEN 1 ELSE 0 END)
      + (CASE WHEN v.is_map = 1 AND v.valuenum < 65 THEN 1 ELSE 0 END)
      + (CASE WHEN v.is_sbp = 1 AND v.valuenum < 90 THEN 1 ELSE 0 END)
      + (CASE WHEN v.is_rr = 1 AND v.valuenum > 25 THEN 1 ELSE 0 END)
      + (CASE WHEN v.is_spo2 = 1 AND v.valuenum < 90 THEN 1 ELSE 0 END)
    ) AS total_abnormal_flags
  FROM vitals_72h v
  GROUP BY v.subject_id, v.hadm_id, v.stay_id
),

-- combine per-stay metrics with icu stay info (los) and admission mortality
per_stay_final AS (
  SELECT
    psm.*,
    ic.los,
    ic.has_se_admission,
    a.hospital_expire_flag,
    -- observation window hours (may be less than or equal to 72)
    SAFE_DIVIDE(
      TIMESTAMP_DIFF(psm.window_end, psm.intime, SECOND),
      3600.0
    ) AS window_hours,
    -- vital instability index: abnormal events per hour (null if no window_hours)
    CASE WHEN SAFE_DIVIDE(
                TIMESTAMP_DIFF(psm.window_end, psm.intime, SECOND),
                3600.0
             ) > 0
         THEN psm.total_abnormal_flags / SAFE_DIVIDE(
                                      TIMESTAMP_DIFF(psm.window_end, psm.intime, SECOND),
                                      3600.0
                                    )
         ELSE NULL
    END AS vital_instability_index,
    -- per-stay burdens (fractions); null if no measurements of that type
    CASE WHEN psm.hr_count > 0 THEN psm.hr_tachy_count / psm.hr_count ELSE NULL END AS tachy_burden,
    CASE WHEN psm.map_count > 0 THEN psm.map_low_count / psm.map_count ELSE NULL END AS map65_burden
  FROM per_stay_metrics psm
  JOIN icustays_labeled ic
    USING (subject_id, hadm_id, stay_id)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    USING (subject_id, hadm_id)
),

-- label each stay with cohort
cohorted AS (
  SELECT
    CASE WHEN has_se_admission = 1 THEN 'status_epilepticus' ELSE 'general_icu' END AS cohort_label,
    subject_id, hadm_id, stay_id,
    vital_instability_index,
    tachy_burden,
    map65_burden,
    los,
    hospital_expire_flag
  FROM per_stay_final
),

-- compute approximate quantiles array for vital_instability_index per cohort
cohort_quantiles AS (
  SELECT
    cohort_label,
    APPROX_QUANTILES(vital_instability_index, 100) AS quantiles
  FROM cohorted
  GROUP BY cohort_label
),

-- compute other cohort-level aggregated statistics
cohort_stats AS (
  SELECT
    cohort_label,
    COUNT(*) AS n_stays,
    AVG(vital_instability_index) AS mean_vital_instability_index,
    AVG(tachy_burden) AS mean_tachy_burden,
    AVG(map65_burden) AS mean_map65_burden,
    AVG(los) AS mean_icu_los_days,
    SAFE_DIVIDE(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), COUNT(*)) AS hospital_mortality_rate
  FROM cohorted
  GROUP BY cohort_label
)

-- Final join: attach quantiles and select requested percentiles
SELECT
  s.cohort_label,
  s.n_stays,
  s.mean_vital_instability_index,
  q.quantiles[OFFSET(25)] AS vii_p25,
  q.quantiles[OFFSET(50)] AS vii_p50,
  q.quantiles[OFFSET(75)] AS vii_p75,
  q.quantiles[OFFSET(90)] AS vii_p90,
  s.mean_tachy_burden,
  s.mean_map65_burden,
  s.mean_icu_los_days,
  s.hospital_mortality_rate,
  q.quantiles AS vii_approx_quantiles_array
FROM cohort_stats s
LEFT JOIN cohort_quantiles q
  USING (cohort_label)
ORDER BY s.cohort_label;