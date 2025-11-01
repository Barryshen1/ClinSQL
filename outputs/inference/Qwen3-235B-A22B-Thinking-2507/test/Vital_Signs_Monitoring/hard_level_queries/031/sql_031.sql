WITH base_cohort AS (
  SELECT 
    icu.stay_id,
    icu.hadm_id,
    icu.subject_id,
    icu.intime,
    icu.los AS icu_los,
    adm.hospital_expire_flag,
    -- Calculate age at admission
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    -- Age between 63 and 73
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 63 AND 73
    -- Post-op: must have at least one procedure
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
      WHERE proc.hadm_id = icu.hadm_id
        AND DATE(proc.chartdate) <= DATE(icu.intime)
    )
),
instability_metrics AS (
  SELECT 
    bc.*,
    -- Count fever events (>38.5°C)
    COALESCE((
      SELECT COUNT(*)
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.stay_id = bc.stay_id
        AND ce.itemid = 223762
        AND ce.valuenum > 38.5
        AND ce.valuenum IS NOT NULL
    ), 0) AS fever_count,
    -- Count SpO2 < 90% events
    COALESCE((
      SELECT COUNT(*)
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.stay_id = bc.stay_id
        AND ce.itemid IN (220277, 225312)
        AND ce.valuenum < 90
        AND ce.valuenum IS NOT NULL
    ), 0) AS spo2_count,
    -- Count RR > 20 events
    COALESCE((
      SELECT COUNT(*)
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.stay_id = bc.stay_id
        AND ce.itemid IN (220210, 224690, 224422)
        AND ce.valuenum > 20
        AND ce.valuenum IS NOT NULL
    ), 0) AS rr_count
  FROM base_cohort bc
),
cohort_with_score AS (
  SELECT 
    *,
    fever_count + spo2_count + rr_count AS instability_score
  FROM instability_metrics
),
cohort_with_quartile AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score DESC) AS quartile
  FROM cohort_with_score
),
top_quartile_95th AS (
  SELECT 
    APPROX_PERCENTILE(instability_score, 0.95) AS instability_score_95th
  FROM cohort_with_quartile
  WHERE quartile = 1
),
group_metrics AS (
  SELECT 
    CASE WHEN quartile = 1 THEN 'top_quartile' ELSE 'rest' END AS group_label,
    AVG(fever_count) AS avg_fever_episodes,
    AVG(spo2_count) AS avg_spo2_episodes,
    AVG(rr_count) AS avg_rr_episodes,
    AVG(icu_los) AS avg_icu_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort_with_quartile
  GROUP BY group_label
)
SELECT 
  gm.group_label,
  CASE WHEN gm.group_label = 'top_quartile' THEN tq95.instability_score_95th ELSE NULL END AS instability_score_95th,
  gm.avg_fever_episodes,
  gm.avg_spo2_episodes,
  gm.avg_rr_episodes,
  gm.avg_icu_los,
  gm.mortality_rate
FROM group_metrics gm
CROSS JOIN top_quartile_95th tq95
ORDER BY gm.group_label;