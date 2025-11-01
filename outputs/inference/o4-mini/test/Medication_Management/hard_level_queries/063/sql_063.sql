WITH pneumonia_dx AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
         AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%pneumonia%'
  GROUP BY
    d.subject_id, d.hadm_id
),
base_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN pneumonia_dx dx
      ON a.subject_id = dx.subject_id
         AND a.hadm_id = dx.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
),
meds_24h AS (
  SELECT
    bc.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count,
    -- emulate BOOL_OR via MAX over 0/1
    MAX(CASE
          WHEN pr.drug IN (
            'fluoxetine','sertraline','paroxetine','citalopram','escitalopram'
          ) THEN 1 ELSE 0
        END) = 1 AS serotonergic_risk
  FROM
    base_cohort bc
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON bc.subject_id = pr.subject_id
         AND bc.hadm_id = pr.hadm_id
         AND pr.starttime BETWEEN bc.admittime AND TIMESTAMP_ADD(bc.admittime, INTERVAL 24 HOUR)
  GROUP BY
    bc.hadm_id
),
cohort_with_meds AS (
  SELECT
    bc.*,
    m.med_count,
    m.serotonergic_risk
  FROM
    base_cohort bc
    LEFT JOIN meds_24h m
      ON bc.hadm_id = m.hadm_id
),
icu_flag AS (
  SELECT DISTINCT
    subject_id,
    hadm_id,
    TRUE AS in_icu
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),
final_cohort AS (
  SELECT
    cwm.*,
    IFNULL(i.in_icu, FALSE) AS in_icu,
    TIMESTAMP_DIFF(cwm.dischtime, cwm.admittime, HOUR) AS los_hours
  FROM
    cohort_with_meds cwm
    LEFT JOIN icu_flag i
      ON cwm.subject_id = i.subject_id
         AND cwm.hadm_id = i.hadm_id
),
-- Medication complexity distribution
med_stats AS (
  SELECT
    AVG(med_count) AS mean_med_count,
    APPROX_QUANTILES(med_count, 4)[OFFSET(1)] AS p25_med_count,
    APPROX_QUANTILES(med_count, 4)[OFFSET(2)] AS p50_med_count,
    APPROX_QUANTILES(med_count, 4)[OFFSET(3)] AS p75_med_count
  FROM
    final_cohort
),
-- LOS & mortality by group
group_summary AS (
  SELECT
    group_label,
    COUNT(*) AS n_patients,
    AVG(los_hours) AS avg_los,
    SUM(hospital_expire_flag) * 1.0 / COUNT(*) AS mortality_rate,
    APPROX_QUANTILES(los_hours, 4)[OFFSET(3)] AS los_75th
  FROM (
    SELECT
      *,
      CASE
        WHEN serotonergic_risk THEN 'serotonergic_risk'
        WHEN in_icu THEN 'icu_patients'
        ELSE 'other'
      END AS group_label
    FROM
      final_cohort
  )
  WHERE group_label IN ('serotonergic_risk','icu_patients')
  GROUP BY
    group_label
),
-- Top-quartile subgroup outcomes
top_quartile AS (
  SELECT
    gs.group_label,
    gs.los_75th,
    COUNT(fc.hadm_id) AS n_top_q,
    AVG(fc.hospital_expire_flag) AS top_q_mortality
  FROM
    group_summary gs
    JOIN final_cohort fc
      ON (CASE
            WHEN fc.serotonergic_risk THEN 'serotonergic_risk'
            WHEN fc.in_icu THEN 'icu_patients'
          END) = gs.group_label
     AND fc.los_hours >= gs.los_75th
  GROUP BY
    gs.group_label, gs.los_75th
)

SELECT
  'Medication Complexity Distribution (48–58y Male Pneumonia)' AS metric,
  ms.mean_med_count,
  ms.p25_med_count,
  ms.p50_med_count,
  ms.p75_med_count
FROM med_stats ms

UNION ALL

SELECT
  CONCAT('Overall outcomes: ', group_label) AS metric,
  gs.avg_los AS mean_med_count,
  gs.mortality_rate AS p25_med_count,
  NULL AS p50_med_count,
  NULL AS p75_med_count
FROM group_summary gs

UNION ALL

SELECT
  CONCAT('Top-quartile LOS outcomes: ', group_label) AS metric,
  tq.los_75th AS mean_med_count,
  tq.top_q_mortality AS p25_med_count,
  NULL AS p50_med_count,
  NULL AS p75_med_count
FROM top_quartile tq

ORDER BY metric;