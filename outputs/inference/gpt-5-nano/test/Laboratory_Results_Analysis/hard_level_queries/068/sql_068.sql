WITH septic_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.subject_id = a.subject_id
   AND i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
    AND di.icd_version = 10
    AND (di.icd_code LIKE 'R65.21%' OR di.icd_code LIKE 'R65.2%')
),

-- Instability indicators within first 48 hours of ICU stay
instability AS (
  SELECT
    sc.hadm_id,
    sc.subject_id,
    sc.stay_id,
    -- SBP <= 100 within 48h
    MAX(CASE
          WHEN di_bp.label LIKE '%systolic%'
               AND ce_bp.charttime BETWEEN sc.admittime AND TIMESTAMP_ADD(sc.admittime, INTERVAL 48 HOUR)
               AND ce_bp.valuenum <= 100
          THEN 1 ELSE 0 END) AS bp_flag,
    -- RR >= 22 within 48h
    MAX(CASE
          WHEN di_rr.label LIKE '%respiratory rate%'
               AND ce_rr.charttime BETWEEN sc.admittime AND TIMESTAMP_ADD(sc.admittime, INTERVAL 48 HOUR)
               AND ce_rr.valuenum >= 22
          THEN 1 ELSE 0 END) AS rr_flag,
    -- GCS < 15 within first 2 ICU days (via Omr)
    MAX(CASE
          WHEN omr_gcs.chartdate BETWEEN DATE(sc.intime) AND DATE(TIMESTAMP_ADD(sc.intime, INTERVAL 2 DAY))
               AND CAST(omr_gcs.result_value AS FLOAT64) < 15
          THEN 1 ELSE 0 END) AS gcs_flag,
    -- instability_score is sum of the three flags
    (
      COALESCE(MAX(CASE
          WHEN di_bp.label LIKE '%systolic%'
               AND ce_bp.charttime BETWEEN sc.admittime AND TIMESTAMP_ADD(sc.admittime, INTERVAL 48 HOUR)
               AND ce_bp.valuenum <= 100
          THEN 1 ELSE 0 END), 0)
      +
      COALESCE(MAX(CASE
          WHEN di_rr.label LIKE '%respiratory rate%'
               AND ce_rr.charttime BETWEEN sc.admittime AND TIMESTAMP_ADD(sc.admittime, INTERVAL 48 HOUR)
               AND ce_rr.valuenum >= 22
          THEN 1 ELSE 0 END), 0)
      +
      COALESCE(MAX(CASE
          WHEN omr_gcs.chartdate BETWEEN DATE(sc.intime) AND DATE(TIMESTAMP_ADD(sc.intime, INTERVAL 2 DAY))
               AND CAST(omr_gcs.result_value AS FLOAT64) < 15
          THEN 1 ELSE 0 END), 0)
    ) AS instability_score
  FROM septic_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_bp
    ON ce_bp.subject_id = sc.subject_id
   AND ce_bp.hadm_id = sc.hadm_id
   AND ce_bp.stay_id = sc.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di_bp
    ON ce_bp.itemid = di_bp.itemid
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce_rr
    ON ce_rr.subject_id = sc.subject_id
   AND ce_rr.hadm_id = sc.hadm_id
   AND ce_rr.stay_id = sc.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di_rr
    ON ce_rr.itemid = di_rr.itemid
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.omr` AS omr_gcs
    ON omr_gcs.subject_id = sc.subject_id
   AND omr_gcs.chartdate BETWEEN DATE(sc.intime) AND DATE(TIMESTAMP_ADD(sc.intime, INTERVAL 2 DAY))
  GROUP BY sc.hadm_id, sc.subject_id, sc.stay_id
),

lab_events_septic AS (
  SELECT a.hadm_id, a.subject_id, labe.charttime, labe.valuenum, labe.ref_range_lower, labe.ref_range_upper,
         CASE WHEN labe.valuenum IS NULL THEN 0
              WHEN labe.ref_range_lower IS NOT NULL AND labe.valuenum < labe.ref_range_lower THEN 1
              WHEN labe.ref_range_upper IS NOT NULL AND labe.valuenum > labe.ref_range_upper THEN 1
              ELSE 0 END AS is_abnormal
  FROM septic_cohort sc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON a.hadm_id = sc.hadm_id AND a.subject_id = sc.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS labe ON labe.subject_id = a.subject_id AND labe.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS item ON labe.itemid = item.itemid
  WHERE labe.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
),

lab_summary_septic AS (
  SELECT hadm_id, SUM(is_abnormal) AS abnormal_lab_count, COUNT(*) AS total_lab_count
  FROM lab_events_septic
  GROUP BY hadm_id
),

lab_events_general AS (
  SELECT a.hadm_id, labe.charttime, labe.valuenum, labe.ref_range_lower, labe.ref_range_upper,
         CASE WHEN labe.valuenum IS NULL THEN 0
              WHEN labe.ref_range_lower IS NOT NULL AND labe.valuenum < labe.ref_range_lower THEN 1
              WHEN labe.ref_range_upper IS NOT NULL AND labe.valuenum > labe.ref_range_upper THEN 1
              ELSE 0 END AS is_abnormal
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS labe ON labe.subject_id = a.subject_id AND labe.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS item ON labe.itemid = item.itemid
  WHERE labe.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
),

lab_summary_general AS (
  SELECT hadm_id, SUM(is_abnormal) AS abnormal_lab_count, COUNT(*) AS total_lab_count
  FROM lab_events_general
  GROUP BY hadm_id
),

los_mortality AS (
  SELECT sc.hadm_id, sc.subject_id, sc.admittime, sc.dischtime, sc.deathtime, sc.hospital_expire_flag
  FROM septic_cohort sc
  LEFT JOIN instability inst ON inst.hadm_id = sc.hadm_id AND inst.subject_id = sc.subject_id AND inst.stay_id = sc.stay_id
),

inst_q AS (
  SELECT (APPROX_QUANTILES(instability_score, 4)[OFFSET(1)]) AS instability_q1,
         (APPROX_QUANTILES(instability_score, 4)[OFFSET(2)]) AS instability_median,
         (APPROX_QUANTILES(instability_score, 4)[OFFSET(3)]) AS instability_q3
  FROM instability
)

SELECT
  inst_q.instability_q1,
  inst_q.instability_median,
  inst_q.instability_q3,
  (inst_q.instability_q3 - inst_q.instability_q1) AS instability_iqr,
  -- abnormal lab frequency: septic vs general
  (SELECT SUM(abnormal_lab_count) / NULLIF(SUM(total_lab_count), 0) FROM lab_summary_septic) AS septic_abnormal_lab_freq,
  (SELECT SUM(abnormal_lab_count) / NULLIF(SUM(total_lab_count), 0) FROM lab_summary_general) AS general_abnormal_lab_freq,
  -- LOS and mortality for septic cohort
  (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) FROM los_mortality) AS coh_avg_los_days,
  (SELECT AVG(CASE WHEN hospital_expire_flag = 1 OR deathtime IS NOT NULL THEN 1.0 ELSE 0.0 END) FROM los_mortality) AS coh_mortality_rate
FROM inst_q
LIMIT 1;