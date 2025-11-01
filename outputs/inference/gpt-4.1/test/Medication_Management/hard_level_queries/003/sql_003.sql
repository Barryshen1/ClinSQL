WITH cohort AS (
  -- Male inpatients aged 39-49
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),
status_epilepticus AS (
  -- Admissions with status epilepticus diagnosis
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%status epilepticus%'
),
meds_24h AS (
  -- Medications administered in first 24h of admission
  SELECT
    c.subject_id,
    c.hadm_id,
    pr.drug,
    pr.starttime
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  WHERE
    pr.starttime >= c.admittime
    AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
),
med_complexity AS (
  -- Medication complexity per admission (distinct drugs in first 24h)
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT LOWER(drug)) AS med_complexity
  FROM
    meds_24h
  GROUP BY
    subject_id, hadm_id
),
interaction_flags AS (
  -- Flag QT-prolonging and bleeding-risk interactions
  SELECT
    m.subject_id,
    m.hadm_id,
    -- QT-prolonging drugs list (example, expand as needed)
    SUM(CASE WHEN LOWER(m.drug) IN (
      'amiodarone', 'haloperidol', 'ondansetron', 'ciprofloxacin', 'levofloxacin', 'methadone', 'quinidine', 'sotalol', 'azithromycin', 'chlorpromazine'
    ) THEN 1 ELSE 0 END) AS qt_drug_count,
    -- Bleeding-risk drugs list (example, expand as needed)
    SUM(CASE WHEN LOWER(m.drug) IN (
      'warfarin', 'heparin', 'enoxaparin', 'aspirin', 'clopidogrel', 'apixaban', 'rivaroxaban', 'dabigatran', 'ticagrelor'
    ) THEN 1 ELSE 0 END) AS bleed_drug_count
  FROM
    meds_24h m
  GROUP BY
    m.subject_id, m.hadm_id
),
main AS (
  -- Combine all info per admission
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    CASE WHEN se.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_status_epilepticus,
    mc.med_complexity,
    i.qt_drug_count,
    i.bleed_drug_count,
    CASE WHEN i.qt_drug_count >= 2 THEN 1 ELSE 0 END AS qt_interaction,
    CASE WHEN i.bleed_drug_count >= 2 THEN 1 ELSE 0 END AS bleed_interaction,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los
  FROM
    cohort c
    LEFT JOIN status_epilepticus se
      ON c.subject_id = se.subject_id AND c.hadm_id = se.hadm_id
    LEFT JOIN med_complexity mc
      ON c.subject_id = mc.subject_id AND c.hadm_id = mc.hadm_id
    LEFT JOIN interaction_flags i
      ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
),
percentiles AS (
  -- Compute percentile rank for medication complexity
  SELECT
    subject_id,
    hadm_id,
    med_complexity,
    PERCENT_RANK() OVER (ORDER BY med_complexity) AS med_complexity_percentile
  FROM
    main
),
main_with_percentile AS (
  SELECT
    m.*,
    p.med_complexity_percentile
  FROM
    main m
    LEFT JOIN percentiles p
      ON m.subject_id = p.subject_id AND m.hadm_id = p.hadm_id
),
summary AS (
  -- Summary stats for each group
  SELECT
    CASE
      WHEN is_status_epilepticus = 1 AND qt_interaction = 1 THEN 'Status Epilepticus + QT Interaction'
      WHEN is_status_epilepticus = 1 AND bleed_interaction = 1 THEN 'Status Epilepticus + Bleed Interaction'
      WHEN is_status_epilepticus = 1 THEN 'Status Epilepticus'
      WHEN qt_interaction = 1 THEN 'QT Interaction'
      WHEN bleed_interaction = 1 THEN 'Bleed Interaction'
      ELSE 'General'
    END AS group_label,
    COUNT(*) AS n_admissions,
    AVG(med_complexity) AS avg_med_complexity,
    APPROX_QUANTILES(med_complexity, 2)[OFFSET(1)] AS median_med_complexity,
    AVG(med_complexity_percentile) AS avg_percentile,
    APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
    AVG(los) AS avg_los,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate
  FROM
    main_with_percentile
  GROUP BY
    group_label
),
top_quartile AS (
  -- Admissions in top quartile for medication complexity
  SELECT
    *
  FROM
    main_with_percentile
  WHERE
    med_complexity_percentile >= 0.75
)
SELECT
  'Summary by Group' AS section,
  *
FROM
  summary

UNION ALL

SELECT
  'Top Quartile LOS & Mortality' AS section,
  group_label,
  COUNT(*) AS n_admissions,
  APPROX_QUANTILES(los, 2)[OFFSET(1)] AS median_los,
  AVG(los) AS avg_los,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate,
  NULL AS avg_med_complexity,
  NULL AS median_med_complexity,
  NULL AS avg_percentile
FROM (
  SELECT
    CASE
      WHEN is_status_epilepticus = 1 AND qt_interaction = 1 THEN 'Status Epilepticus + QT Interaction'
      WHEN is_status_epilepticus = 1 AND bleed_interaction = 1 THEN 'Status Epilepticus + Bleed Interaction'
      WHEN is_status_epilepticus = 1 THEN 'Status Epilepticus'
      WHEN qt_interaction = 1 THEN 'QT Interaction'
      WHEN bleed_interaction = 1 THEN 'Bleed Interaction'
      ELSE 'General'
    END AS group_label,
    los,
    hospital_expire_flag
  FROM
    top_quartile
)
GROUP BY
  section, group_label
ORDER BY
  section, group_label;