WITH asthma_cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    adm.deathtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON i.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON i.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON i.subject_id = di.subject_id
   AND i.hadm_id = di.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND di.icd_code LIKE '493%'  -- asthma ICD-9 codes
),
non_asthma_cohort AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los,
    adm.deathtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON i.hadm_id = adm.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON i.subject_id = pat.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON i.subject_id = di.subject_id
   AND i.hadm_id = di.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND (di.icd_code NOT LIKE '493%')
),
-- Timepoints (first 72h) for asthma cohort
asthma_timepoints AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    i.intime,
    ce.charttime,
    MAX(CASE WHEN LOWER(di.label) LIKE '%heart rate%' THEN ce.valuenum END) AS hr,
    MAX(CASE WHEN LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%' THEN ce.valuenum END) AS map,
    MAX(CASE WHEN LOWER(di.label) LIKE '%respiratory rate%' THEN ce.valuenum END) AS rr,
    MAX(CASE WHEN LOWER(di.label) LIKE '%temperature%' THEN ce.valuenum END) AS temp,
    MAX(CASE WHEN LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%' THEN ce.valuenum END) AS spo2
  FROM
    asthma_cohort AS a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.subject_id = i.subject_id
   AND a.hadm_id = i.hadm_id
   AND a.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON i.subject_id = ce.subject_id
   AND i.hadm_id = ce.hadm_id
   AND i.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN i.intime
        AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY a.subject_id, a.hadm_id, a.stay_id, i.intime, ce.charttime
),
non_asthma_timepoints AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.stay_id,
    i.intime,
    ce.charttime,
    MAX(CASE WHEN LOWER(di.label) LIKE '%heart rate%' THEN ce.valuenum END) AS hr,
    MAX(CASE WHEN LOWER(di.label) LIKE '%mean arterial pressure%' OR LOWER(di.label) LIKE '%map%' THEN ce.valuenum END) AS map,
    MAX(CASE WHEN LOWER(di.label) LIKE '%respiratory rate%' THEN ce.valuenum END) AS rr,
    MAX(CASE WHEN LOWER(di.label) LIKE '%temperature%' THEN ce.valuenum END) AS temp,
    MAX(CASE WHEN LOWER(di.label) LIKE '%spo2%' OR LOWER(di.label) LIKE '%oxygen saturation%' THEN ce.valuenum END) AS spo2
  FROM
    non_asthma_cohort AS a
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.subject_id = i.subject_id
   AND a.hadm_id = i.hadm_id
   AND a.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON i.subject_id = ce.subject_id
   AND i.hadm_id = ce.hadm_id
   AND i.stay_id = ce.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  WHERE ce.charttime BETWEEN i.intime
        AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  GROUP BY a.subject_id, a.hadm_id, a.stay_id, i.intime, ce.charttime
),
-- Instability score per timepoint
asthma_instability AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.stay_id,
    t.charttime,
    IFNULL(t.hr, 0) < 60 OR IFNULL(t.hr, 0) > 100 AS hr_abn,
    IFNULL(t.map, 0) < 65 OR IFNULL(t.map, 0) > 105 AS map_abn,
    IFNULL(t.rr, 0) < 12 OR IFNULL(t.rr, 0) > 20 AS rr_abn,
    IFNULL(t.temp, 0) < 36 OR IFNULL(t.temp, 0) > 37.5 AS temp_abn,
    IFNULL(t.spo2, 0) < 92 AS spo2_abn,
    (CASE WHEN IFNULL(t.hr,0) = 0 THEN 0
          ELSE IF (IFNULL(t.hr,0) < 60 OR IFNULL(t.hr,0) > 100, 1, 0) END) +
    (CASE WHEN IFNULL(t.map,0) = 0 THEN 0
          ELSE IF (IFNULL(t.map,0) < 65 OR IFNULL(t.map,0) > 105, 1, 0) END) +
    (CASE WHEN IFNULL(t.rr,0) = 0 THEN 0
          ELSE IF (IFNULL(t.rr,0) < 12 OR IFNULL(t.rr,0) > 20, 1, 0) END) +
    (CASE WHEN IFNULL(t.temp,0) = 0 THEN 0
          ELSE IF (IFNULL(t.temp,0) < 36 OR IFNULL(t.temp,0) > 37.5, 1, 0) END) +
    (CASE WHEN IFNULL(t.spo2,0) = 0 THEN 0
          ELSE IF (IFNULL(t.spo2,0) < 92, 1, 0) END) AS instability_score
  FROM asthma_timepoints AS t
),
nonasthma_instability AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.stay_id,
    t.charttime,
    IFNULL(t.hr, 0) < 60 OR IFNULL(t.hr, 0) > 100 AS hr_abn,
    IFNULL(t.map, 0) < 65 OR IFNULL(t.map, 0) > 105 AS map_abn,
    IFNULL(t.rr, 0) < 12 OR IFNULL(t.rr, 0) > 20 AS rr_abn,
    IFNULL(t.temp, 0) < 36 OR IFNULL(t.temp, 0) > 37.5 AS temp_abn,
    IFNULL(t.spo2, 0) < 92 AS spo2_abn,
    (CASE WHEN IFNULL(t.hr,0) = 0 THEN 0
          ELSE IF (IFNULL(t.hr,0) < 60 OR IFNULL(t.hr,0) > 100, 1, 0) END) +
    (CASE WHEN IFNULL(t.map,0) = 0 THEN 0
          ELSE IF (IFNULL(t.map,0) < 65 OR IFNULL(t.map,0) > 105, 1, 0) END) +
    (CASE WHEN IFNULL(t.rr,0) = 0 THEN 0
          ELSE IF (IFNULL(t.rr,0) < 12 OR IFNULL(t.rr,0) > 20, 1, 0) END) +
    (CASE WHEN IFNULL(t.temp,0) = 0 THEN 0
          ELSE IF (IFNULL(t.temp,0) < 36 OR IFNULL(t.temp,0) > 37.5, 1, 0) END) +
    (CASE WHEN IFNULL(t.spo2,0) = 0 THEN 0
          ELSE IF (IFNULL(t.spo2,0) < 92, 1, 0) END) AS instability_score
  FROM non_asthma_timepoints AS t
),
-- Summary stats: compute via scalar subqueries to avoid grouping/analytic mix
asthma_summary AS (
  SELECT
    (SELECT STDDEV(instability_score) FROM asthma_instability) AS sd_instability,
    (SELECT PERCENTILE_CONT(instability_score, 0.25) FROM asthma_instability) AS p25,
    (SELECT PERCENTILE_CONT(instability_score, 0.50) FROM asthma_instability) AS p50,
    (SELECT PERCENTILE_CONT(instability_score, 0.75) FROM asthma_instability) AS p75,
    (SELECT PERCENTILE_CONT(instability_score, 0.95) FROM asthma_instability) AS p95
),
nonasthma_summary AS (
  SELECT
    (SELECT STDDEV(instability_score) FROM nonasthma_instability) AS sd_instability,
    (SELECT PERCENTILE_CONT(instability_score, 0.25) FROM nonasthma_instability) AS p25,
    (SELECT PERCENTILE_CONT(instability_score, 0.50) FROM nonasthma_instability) AS p50,
    (SELECT PERCENTILE_CONT(instability_score, 0.75) FROM nonasthma_instability) AS p75,
    (SELECT PERCENTILE_CONT(instability_score, 0.95) FROM nonasthma_instability) AS p95
),
asthma_los AS (
  SELECT AVG(icu_los) AS mean_los_hours, COUNT(*) AS n_patients
  FROM asthma_cohort
),
nonasthma_los AS (
  SELECT AVG(icu_los) AS mean_los_hours, COUNT(*) AS n_patients
  FROM non_asthma_cohort
),
asthma_mortality AS (
  SELECT
    100.0 * SUM(CASE WHEN deathtime IS NOT NULL OR hospital_expire_flag = '1' THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
  FROM asthma_cohort AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON a.hadm_id = adm.hadm_id
),
nonasthma_mortality AS (
  SELECT
    100.0 * SUM(CASE WHEN deathtime IS NOT NULL OR hospital_expire_flag = '1' THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
  FROM non_asthma_cohort AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON a.hadm_id = adm.hadm_id
)

SELECT
  a.sd_instability AS asthma_sd_instability,
  a.p25 AS asthma_p25,
  a.p50 AS asthma_p50,
  a.p75 AS asthma_p75,
  a.p95 AS asthma_p75_95,          -- notice: alias for clarity
  al.mean_los_hours AS asthma_mean_los_hours,
  am.mortality_rate AS asthma_mortality_rate,
  na.sd_instability AS nonas_sd_instability,
  na.p25 AS nonas_p25,
  na.p50 AS nonas_p50,
  na.p75 AS nonas_p75,
  na.p95 AS nonas_p95,
  nol.mean_los_hours AS nonas_mean_los_hours,
  nom.mortality_rate AS nonas_mortality_rate
FROM asthma_summary AS a
CROSS JOIN asthma_los AS al
CROSS JOIN asthma_mortality AS am
CROSS JOIN nonasthma_summary AS na
CROSS JOIN nonasthma_los AS nol
CROSS JOIN nonasthma_mortality AS nom;