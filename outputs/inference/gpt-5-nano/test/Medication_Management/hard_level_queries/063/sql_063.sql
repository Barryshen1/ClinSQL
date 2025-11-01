WITH pneumonia_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE (p.gender IN ('Male','M'))
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 48 AND 58
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),
meds_within24 AS (
  SELECT
    pc.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count,
    MAX(CASE
          WHEN LOWER(pr.drug) LIKE '%fluoxetine%' OR
               LOWER(pr.drug) LIKE '%sertraline%' OR
               LOWER(pr.drug) LIKE '%citalopram%' OR
               LOWER(pr.drug) LIKE '%escitalopram%' OR
               LOWER(pr.drug) LIKE '%paroxetine%' OR
               LOWER(pr.drug) LIKE '%venlafaxine%' OR
               LOWER(pr.drug) LIKE '%duloxetine%' OR
               LOWER(prug) LIKE '%phenelzine%' OR
               LOWER(pr.drug) LIKE '%isocarboxazid%' OR
               LOWER(pr.drug) LIKE '%tranylcypromine%' OR
               LOWER(pr.drug) LIKE '%sumatriptan%'
          THEN 1
          ELSE 0
        END) AS serotonergic_flag
  FROM pneumonia_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.subject_id = pc.subject_id
   AND pr.hadm_id = pc.hadm_id
   AND pr.starttime >= pc.admittime
   AND pr.starttime <= TIMESTAMP_ADD(pc.admittime, INTERVAL 24 HOUR)
  GROUP BY pc.hadm_id
),
icu_flags AS (
  SELECT hadm_id, 1 AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
cohort AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime,
    pc.deathtime,
    pc.hospital_expire_flag,
    pc.gender,
    pc.age_at_adm,
    COALESCE(m.med_count, 0) AS med_count,
    COALESCE(m.serotonergic_flag, 0) AS serotonergic_flag,
    COALESCE(i.icu_flag, 0) AS icu_flag,
    TIMESTAMP_DIFF(pc.dischtime, pc.admittime, SECOND) / 3600.0 AS los_hours,
    CASE
      WHEN pc.hospital_expire_flag = 1 OR pc.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS mortality
  FROM pneumonia_cohort pc
  LEFT JOIN meds_within24 m
    ON pc.hadm_id = m.hadm_id
  LEFT JOIN icu_flags i
    ON pc.hadm_id = i.hadm_id
)

-- Produce three group results without UNNEST on APPROX_QUANTILES
SELECT
  'medication_complexity_overall' AS group_label,
  NULL AS los_mean,
  NULL AS los_p25,
  NULL AS los_p50,
  NULL AS los_p75,
  NULL AS mortality_rate,
  med_mean,
  med_p25,
  med_p50,
  med_p75
FROM (
  SELECT AVG(med_count) AS med_mean,
         med_q.quantiles[OFFSET(1)] AS med_p25,
         med_q.quantiles[OFFSET(2)] AS med_p50,
         med_q.quantiles[OFFSET(3)] AS med_p75
  FROM meds_within24
  CROSS JOIN (SELECT APPROX_QUANTILES(med_count, 4) AS quantiles FROM meds_within24) AS med_q
) AS t

UNION ALL

SELECT
  'serotonergic_risk' AS group_label,
  los_mean,
  los_p25,
  los_p50,
  los_p75,
  mortality_rate,
  NULL AS med_mean,
  NULL AS med_p25,
  NULL AS med_p50,
  NULL AS med_p75
FROM (
  SELECT AVG(los_hours) AS los_mean,
         q.quantiles[OFFSET(1)] AS los_p25,
         q.quantiles[OFFSET(2)] AS los_p50,
         q.quantiles[OFFSET(3)] AS los_p75,
         AVG(mortality) AS mortality_rate
  FROM cohort
  CROSS JOIN (SELECT APPROX_QUANTILES(los_hours, 4) AS quantiles FROM cohort WHERE serotonergic_flag = 1) AS q
  WHERE serotonergic_flag = 1
) AS t

UNION ALL

SELECT
  'icu_patients' AS group_label,
  los_mean,
  los_p25,
  los_p50,
  los_p75,
  mortality_rate,
  NULL AS med_mean,
  NULL AS med_p25,
  NULL AS med_p50,
  NULL AS med_p75
FROM (
  SELECT AVG(los_hours) AS los_mean,
         q.quantiles[OFFSET(1)] AS los_p25,
         q.quantiles[OFFSET(2)] AS los_p50,
         q.quantiles[OFFSET(3)] AS los_p75,
         AVG(mortality) AS mortality_rate
  FROM cohort
  CROSS JOIN (SELECT APPROX_QUANTILES(los_hours, 4) AS quantiles FROM cohort WHERE icu_flag = 1) AS q
  WHERE icu_flag = 1
) AS t;