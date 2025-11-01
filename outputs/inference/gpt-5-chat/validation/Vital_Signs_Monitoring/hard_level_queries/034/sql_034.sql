WITH mixed_shock_females AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.anchor_age,
    pat.gender,
    icu.intime,
    icu.outtime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON dx.subject_id = icu.subject_id
   AND dx.hadm_id = icu.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code
   AND dx.icd_version = ddx.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 60 AND 70
    AND LOWER(ddx.long_title) LIKE '%mixed shock%'
),
vitals_48h AS (
  SELECT
    msf.subject_id,
    msf.hadm_id,
    msf.stay_id,
    di.label,
    ce.charttime,
    ce.valuenum
  FROM mixed_shock_females msf
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = msf.subject_id
   AND ce.stay_id = msf.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN msf.intime AND DATETIME_ADD(msf.intime, INTERVAL 48 HOUR)
    AND LOWER(di.label) IN (
      'mean arterial pressure', 'heart rate'
    )
),
instability_counts AS (
  SELECT
    v.subject_id,
    v.hadm_id,
    v.stay_id,
    SUM(CASE WHEN LOWER(v.label) = 'mean arterial pressure' AND v.valuenum < 65 THEN 1 ELSE 0 END) AS hypotension_events,
    SUM(CASE WHEN LOWER(v.label) = 'heart rate' AND v.valuenum > 100 THEN 1 ELSE 0 END) AS tachycardia_events
  FROM vitals_48h v
  GROUP BY v.subject_id, v.hadm_id, v.stay_id
),
with_outcomes AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.hypotension_events,
    ic.tachycardia_events,
    (ic.hypotension_events + ic.tachycardia_events) AS instability_score,
    msf.los AS icu_los,
    adm.hospital_expire_flag
  FROM instability_counts ic
  JOIN mixed_shock_females msf
    ON ic.subject_id = msf.subject_id
   AND ic.hadm_id = msf.hadm_id
   AND ic.stay_id = msf.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ic.subject_id = adm.subject_id
   AND ic.hadm_id = adm.hadm_id
),
percentiles AS (
  SELECT
    PERCENTILE_CONT(instability_score, 0.95) OVER() AS p95_score,
    PERCENTILE_CONT(instability_score, 0.90) OVER() AS p90_score
  FROM with_outcomes
  QUALIFY ROW_NUMBER() OVER (ORDER BY instability_score DESC) = 1
),
labeled AS (
  SELECT
    w.*,
    p.p95_score,
    p.p90_score,
    CASE WHEN w.instability_score >= p.p90_score THEN 'top_decile' ELSE 'cohort' END AS group_label
  FROM with_outcomes w
  CROSS JOIN percentiles p
)
SELECT
  group_label,
  COUNT(*) AS n_stays,
  AVG(hypotension_events) AS avg_hypotension_events,
  AVG(tachycardia_events) AS avg_tachycardia_events,
  AVG(icu_los) AS avg_icu_los_days,
  AVG(hospital_expire_flag) AS mortality_rate,
  MAX(p95_score) AS cohort_95th_percentile_score
FROM labeled
GROUP BY group_label
ORDER BY group_label;