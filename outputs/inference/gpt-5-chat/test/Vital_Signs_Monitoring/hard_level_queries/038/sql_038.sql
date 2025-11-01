WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.gender,
    pat.anchor_age,
    icu.intime,
    icu.outtime,
    adm.hospital_expire_flag,
    CASE
      WHEN SUM(CASE WHEN LOWER(dx.long_title) LIKE '%status epilepticus%' THEN 1 ELSE 0 END) > 0
      THEN 1 ELSE 0
    END AS status_epilepticus
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dix
    ON icu.hadm_id = dix.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dx
    ON dix.icd_code = dx.icd_code
   AND dix.icd_version = dx.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 63 AND 73
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id,
           pat.gender, pat.anchor_age, icu.intime, icu.outtime, adm.hospital_expire_flag
),

hr_map AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    CASE WHEN itemid IN (211, 220045) THEN valuenum END AS heart_rate,
    CASE WHEN itemid IN (456, 220052) THEN valuenum END AS map
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE itemid IN (211, 220045, 456, 220052)
    AND valuenum IS NOT NULL
),

vitals_72h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    hr_map.heart_rate,
    hr_map.map,
    CASE WHEN hr_map.heart_rate > 100 THEN 1 ELSE 0 END AS tachycardia_flag,
    CASE WHEN hr_map.map < 65 THEN 1 ELSE 0 END AS lowmap_flag
  FROM cohort c
  JOIN hr_map
    ON c.subject_id = hr_map.subject_id
    AND c.stay_id = hr_map.stay_id
    AND hr_map.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
),

patient_level AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.status_epilepticus,
    c.anchor_age,
    c.hospital_expire_flag,
    c.intime,
    c.outtime,
    AVG(0.5 * tachycardia_flag + 0.5 * lowmap_flag) AS mean_vital_instability_index,
    AVG(tachycardia_flag) AS tachy_burden,
    AVG(lowmap_flag) AS lowmap_burden,
    TIMESTAMP_DIFF(c.outtime, c.intime, HOUR) / 24.0 AS icu_los_days
  FROM vitals_72h v
  JOIN cohort c
    ON v.subject_id = c.subject_id
    AND v.stay_id = c.stay_id
  GROUP BY c.subject_id, c.hadm_id, c.stay_id,
           c.status_epilepticus, c.anchor_age, c.hospital_expire_flag, c.intime, c.outtime
),

group_stats AS (
  SELECT
    status_epilepticus,
    COUNT(*) AS n_stays,
    AVG(mean_vital_instability_index) AS mean_index,
    APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(25)] AS p25_index,
    APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(50)] AS p50_index,
    APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(75)] AS p75_index,
    APPROX_QUANTILES(mean_vital_instability_index, 100)[OFFSET(90)] AS p90_index,
    AVG(tachy_burden) AS mean_tachy_burden,
    AVG(lowmap_burden) AS mean_lowmap_burden,
    AVG(icu_los_days) AS mean_icu_los,
    AVG(CAST(hospital_expire_flag AS INT64)) AS mortality_rate
  FROM patient_level
  GROUP BY status_epilepticus
)

SELECT
  CASE WHEN status_epilepticus = 1 THEN 'Status Epilepticus' ELSE 'General ICU' END AS group_label,
  n_stays,
  mean_index,
  p25_index,
  p50_index,
  p75_index,
  p90_index,
  mean_tachy_burden,
  mean_lowmap_burden,
  mean_icu_los,
  mortality_rate
FROM group_stats
ORDER BY status_epilepticus DESC;