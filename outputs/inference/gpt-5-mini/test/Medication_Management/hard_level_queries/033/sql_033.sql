WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON a.subject_id = dx.subject_id AND a.hadm_id = dx.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON dx.icd_code = dd.icd_code AND dx.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 80 AND 90
    AND LOWER(COALESCE(dd.long_title, '')) LIKE '%sepsis%'
),

-- Medications in first 24 hours from prescriptions
meds_prescriptions AS (
  SELECT
    c.hadm_id,
    LOWER(p.drug) AS med,
    p.starttime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON c.hadm_id = p.hadm_id
  WHERE
    p.starttime IS NOT NULL
    AND p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
),

-- Medications in first 24 hours from pharmacy table (dispensations)
meds_pharmacy AS (
  SELECT
    c.hadm_id,
    LOWER(ph.medication) AS med,
    ph.starttime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
      ON c.hadm_id = ph.hadm_id
  WHERE
    ph.starttime IS NOT NULL
    AND ph.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
),

-- Unioned medication list (may include duplicates across sources)
meds_union AS (
  SELECT hadm_id, med FROM meds_prescriptions
  UNION ALL
  SELECT hadm_id, med FROM meds_pharmacy
),

-- Per-admission medication summary: MCS and flags for QT and bleeding medications
patient_med_summary AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    -- medication complexity score = count of distinct medication strings in first 24h
    COALESCE(COUNT(DISTINCT CASE WHEN m.med IS NOT NULL AND TRIM(m.med) <> '' THEN m.med END), 0) AS mcs,
    -- QT-prolonging drug flag (approximate via regex on med name)
    COALESCE(
      BOOL_OR(
        REGEXP_CONTAINS(COALESCE(m.med, ''), r'(amiodarone|haloperidol|azithromycin|ciprofloxacin|levofloxacin|moxifloxacin|sotalol|ondansetron|quinidine|dofetilide|clarithromycin)')
      ), FALSE
    ) AS qt_flag,
    -- Bleeding-risk drug flag (approximate)
    COALESCE(
      BOOL_OR(
        REGEXP_CONTAINS(COALESCE(m.med, ''), r'(warfarin|heparin|enoxaparin|apixaban|rivaroxaban|dabigatran|aspirin|acetylsalicylic|clopidogrel|ticagrelor)')
      ), FALSE
    ) AS bleed_flag
  FROM
    cohort c
    LEFT JOIN meds_union m
      ON c.hadm_id = m.hadm_id
  GROUP BY
    c.hadm_id, c.subject_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

patient_with_percentile AS (
  SELECT
    pms.*,
    (pms.qt_flag AND pms.bleed_flag) AS both_qt_and_bleed,
    CUME_DIST() OVER (ORDER BY pms.mcs) * 100.0 AS mcs_percentile_rank -- percentile 0..100
  FROM
    patient_med_summary pms
),

-- Compute overall quartile thresholds for MCS (approximate)
overall_mcs_quants AS (
  SELECT
    APPROX_QUANTILES(mcs, 4) AS quants -- offsets: 0 (min),1(25th),2(50th),3(75th),4(max)
  FROM
    patient_med_summary
),

-- Extract 75th percentile threshold
mcs_75th AS (
  SELECT quants[OFFSET(3)] AS threshold_mcs
  FROM overall_mcs_quants
),

-- Per-patient LOS in days (admission-level) for later aggregation
patient_with_los AS (
  SELECT
    p.*,
    SAFE_DIVIDE(TIMESTAMP_DIFF(p.dischtime, p.admittime, HOUR), 24.0) AS los_days
  FROM
    patient_with_percentile p
),

-- Summary by group (both_qt_and_bleed vs other)
summary_by_group AS (
  SELECT
    CASE WHEN both_qt_and_bleed THEN 'both_qt_and_bleed' ELSE 'other' END AS group_label,
    COUNT(*) AS n_patients,
    ROUND(AVG(mcs), 2) AS mean_mcs,
    ROUND(STDDEV_POP(mcs), 2) AS sd_mcs,
    APPROX_QUANTILES(mcs, 4) AS mcs_quartiles -- 0,25th,50th,75th,100th
  FROM
    patient_med_summary
  GROUP BY
    group_label
),

-- Top quartile patients
top_quartile_patients AS (
  SELECT
    pwl.*
  FROM
    patient_with_los pwl,
    mcs_75th t
  WHERE
    pwl.mcs >= t.threshold_mcs
)

-- Final output: three logically separate result blocks combined with UNION ALL.
SELECT
  'per_patient' AS result_part,
  p.hadm_id,
  p.subject_id,
  p.mcs,
  ROUND(p.mcs_percentile_rank, 2) AS mcs_percentile_rank,
  p.qt_flag,
  p.bleed_flag,
  p.both_qt_and_bleed,
  ROUND(p.los_days, 3) AS los_days,
  p.hospital_expire_flag,
  NULL AS group_label,
  NULL AS n_patients,
  NULL AS mean_mcs,
  NULL AS sd_mcs,
  NULL AS q25_mcs,
  NULL AS median_mcs,
  NULL AS q75_mcs,
  NULL AS max_mcs,
  NULL AS subgroup,
  NULL AS n_top,
  NULL AS mean_los_days,
  NULL AS median_los_days,
  NULL AS hospital_mortality_percent
FROM
  patient_with_los p

UNION ALL

SELECT
  'group_distribution' AS result_part,
  NULL AS hadm_id,
  NULL AS subject_id,
  NULL AS mcs,
  NULL AS mcs_percentile_rank,
  NULL AS qt_flag,
  NULL AS bleed_flag,
  NULL AS both_qt_and_bleed,
  NULL AS los_days,
  NULL AS hospital_expire_flag,
  sbg.group_label,
  sbg.n_patients,
  sbg.mean_mcs,
  sbg.sd_mcs,
  sbg.mcs_quartiles[OFFSET(1)] AS q25_mcs,
  sbg.mcs_quartiles[OFFSET(2)] AS median_mcs,
  sbg.mcs_quartiles[OFFSET(3)] AS q75_mcs,
  sbg.mcs_quartiles[OFFSET(4)] AS max_mcs,
  NULL AS subgroup,
  NULL AS n_top,
  NULL AS mean_los_days,
  NULL AS median_los_days,
  NULL AS hospital_mortality_percent
FROM
  summary_by_group sbg

UNION ALL

SELECT
  'top_quartile_summary' AS result_part,
  NULL AS hadm_id,
  NULL AS subject_id,
  NULL AS mcs,
  NULL AS mcs_percentile_rank,
  NULL AS qt_flag,
  NULL AS bleed_flag,
  NULL AS both_qt_and_bleed,
  NULL AS los_days,
  NULL AS hospital_expire_flag,
  NULL AS group_label,
  NULL AS n_patients,
  NULL AS mean_mcs,
  NULL AS sd_mcs,
  NULL AS q25_mcs,
  NULL AS median_mcs,
  NULL AS q75_mcs,
  NULL AS max_mcs,
  'overall_top_quartile' AS subgroup,
  COUNT(*) AS n_top,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  (APPROX_QUANTILES(los_days, 4))[OFFSET(2)] AS median_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS hospital_mortality_percent
FROM
  top_quartile_patients

UNION ALL

SELECT
  'top_quartile_summary' AS result_part,
  NULL AS hadm_id,
  NULL AS subject_id,
  NULL AS mcs,
  NULL AS mcs_percentile_rank,
  NULL AS qt_flag,
  NULL AS bleed_flag,
  NULL AS both_qt_and_bleed,
  NULL AS los_days,
  NULL AS hospital_expire_flag,
  NULL AS group_label,
  NULL AS n_patients,
  NULL AS mean_mcs,
  NULL AS sd_mcs,
  NULL AS q25_mcs,
  NULL AS median_mcs,
  NULL AS q75_mcs,
  NULL AS max_mcs,
  CASE WHEN both_qt_and_bleed THEN 'top_quartile_and_both_qt_bleed' ELSE 'top_quartile_other' END AS subgroup,
  COUNT(*) AS n_top,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  (APPROX_QUANTILES(los_days, 4))[OFFSET(2)] AS median_los_days,
  ROUND(100.0 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS hospital_mortality_percent
FROM
  top_quartile_patients
GROUP BY
  CASE WHEN both_qt_and_bleed THEN 'top_quartile_and_both_qt_bleed' ELSE 'top_quartile_other' END

ORDER BY
  result_part, subgroup;