WITH cohort_patients AS (
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime, icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON icu.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND LOWER(d_dx.long_title) LIKE '%acute respiratory failure%'
),

cohort_chartevents AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN di.label = 'MAP' THEN ce.valuenum ELSE NULL END) AS map,
    MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum ELSE NULL END) AS hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN cohort_patients cp
    ON ce.stay_id = cp.stay_id
  WHERE ce.charttime BETWEEN cp.intime AND TIMESTAMP_ADD(cp.intime, INTERVAL 72 HOUR)
    AND di.label IN ('MAP', 'Heart Rate')
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id, ce.charttime
),

cohort_burdens AS (
  SELECT
    stay_id,
    SUM(CASE WHEN map < 65 THEN delta_sec ELSE 0 END) / SUM(delta_sec) AS map_burden,
    SUM(CASE WHEN hr > 100 THEN delta_sec ELSE 0 END) / SUM(delta_sec) AS hr_burden,
    (SUM(CASE WHEN map < 65 THEN delta_sec ELSE 0 END) + SUM(CASE WHEN hr > 100 THEN delta_sec ELSE 0 END)) / SUM(delta_sec) AS instability_score
  FROM (
    SELECT
      stay_id,
      charttime,
      map,
      hr,
      TIMESTAMP_DIFF(LEAD(charttime) OVER (PARTITION BY stay_id ORDER BY charttime), charttime, SECOND) AS delta_sec
    FROM cohort_chartevents
  )
  WHERE delta_sec > 0 AND delta_sec <= 3600
  GROUP BY stay_id
),

cohort_summary AS (
  SELECT
    'cohort' AS group_name,
    COUNT(*) AS n_stays,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS p25_instability,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS median_instability,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_instability,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] - APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS iqr_instability,
    AVG(map_burden) AS avg_map_burden,
    AVG(hr_burden) AS avg_hr_burden,
    AVG(TIMESTAMP_DIFF(icu.outtime, icu.intime, SECOND) / 3600.0) AS avg_icu_los_hours,
    AVG(adm.hospital_expire_flag) AS mortality_rate
  FROM cohort_burdens cb
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON cb.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON icu.hadm_id = adm.hadm_id
),

general_chartevents AS (
  SELECT
    ce.stay_id,
    ce.charttime,
    MAX(CASE WHEN di.label = 'MAP' THEN ce.valuenum ELSE NULL END) AS map,
    MAX(CASE WHEN di.label = 'Heart Rate' THEN ce.valuenum ELSE NULL END) AS hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.label IN ('MAP', 'Heart Rate')
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id, ce.charttime
),

general_burdens AS (
  SELECT
    stay_id,
    SUM(CASE WHEN map < 65 THEN delta_sec ELSE 0 END) / SUM(delta_sec) AS map_burden,
    SUM(CASE WHEN hr > 100 THEN delta_sec ELSE 0 END) / SUM(delta_sec) AS hr_burden,
    (SUM(CASE WHEN map < 65 THEN delta_sec ELSE 0 END) + SUM(CASE WHEN hr > 100 THEN delta_sec ELSE 0 END)) / SUM(delta_sec) AS instability_score
  FROM (
    SELECT
      stay_id,
      charttime,
      map,
      hr,
      TIMESTAMP_DIFF(LEAD(charttime) OVER (PARTITION BY stay_id ORDER BY charttime), charttime, SECOND) AS delta_sec
    FROM general_chartevents
  )
  WHERE delta_sec > 0 AND delta_sec <= 3600
  GROUP BY stay_id
),

general_summary AS (
  SELECT
    'general' AS group_name,
    COUNT(*) AS n_stays,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS p25_instability,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(50)] AS median_instability,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_instability,
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] - APPROX_QUANTILES(instability_score, 100)[OFFSET(25)] AS iqr_instability,
    AVG(map_burden) AS avg_map_burden,
    AVG(hr_burden) AS avg_hr_burden,
    AVG(TIMESTAMP_DIFF(icu.outtime, icu.intime, SECOND) / 3600.0) AS avg_icu_los_hours,
    AVG(adm.hospital_expire_flag) AS mortality_rate
  FROM general_burdens gb
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON gb.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm ON icu.hadm_id = adm.hadm_id
)

SELECT * FROM cohort_summary
UNION ALL
SELECT * FROM general_summary;