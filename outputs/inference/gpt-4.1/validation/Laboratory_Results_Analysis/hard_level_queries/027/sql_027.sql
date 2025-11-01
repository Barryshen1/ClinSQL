WITH lower_gi_bleed_icds AS (
  -- Identify ICD codes for lower GI bleed
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (
    (LOWER(long_title) LIKE '%lower%' AND LOWER(long_title) LIKE '%bleed%')
    OR (LOWER(long_title) LIKE '%rectal%' AND LOWER(long_title) LIKE '%bleed%')
    OR LOWER(long_title) LIKE '%hematochezia%'
    OR LOWER(long_title) LIKE '%melena%'
    OR (LOWER(long_title) LIKE '%diverticulitis%' AND LOWER(long_title) LIKE '%bleed%')
    OR (LOWER(long_title) LIKE '%hemorrhage%' AND (LOWER(long_title) LIKE '%rectum%' OR LOWER(long_title) LIKE '%colon%' OR LOWER(long_title) LIKE '%anus%'))
    OR icd_code IN ('K92.1','K62.5','K55.6','K64.8','K62.6','K57.3','K57.33','569.3','569.86','578.1','578.9')
  )
),
cohort AS (
  -- Get male inpatients aged 89-99 with lower GI bleed
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN lower_gi_bleed_icds icd
    ON dx.icd_code = icd.icd_code AND dx.icd_version = icd.icd_version
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 89 AND 99
),
lab_instability AS (
  -- For each admission, count critical labs in first 72h
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT le.labevent_id) AS lab_instability_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND (
      (le.flag = 'abnormal')
      OR (le.valuenum IS NOT NULL AND le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL
          AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper))
    )
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_labscore AS (
  -- Merge cohort and lab instability score
  SELECT
    c.*,
    IFNULL(l.lab_instability_score, 0) AS lab_instability_score,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR)/24.0 AS los_days
  FROM cohort c
  LEFT JOIN lab_instability l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
),
quintiles AS (
  -- Assign quintiles based on lab instability score
  SELECT
    *,
    NTILE(5) OVER (ORDER BY lab_instability_score) AS quintile
  FROM cohort_with_labscore
),
quintile_stats AS (
  -- Compute stats per quintile
  SELECT
    quintile,
    COUNT(*) AS n_admissions,
    AVG(lab_instability_score) AS avg_lab_instability_score,
    APPROX_QUANTILES(lab_instability_score, 2)[OFFSET(1)] AS median_lab_instability_score,
    AVG(los_days) AS avg_los_days,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM quintiles
  GROUP BY quintile
),
general_inpatient_lab_instability AS (
  -- Compute lab instability score for all admissions
  SELECT
    adm.subject_id,
    adm.hadm_id,
    COUNT(DISTINCT le.labevent_id) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON adm.hadm_id = le.hadm_id
    AND le.charttime BETWEEN adm.admittime AND TIMESTAMP_ADD(adm.admittime, INTERVAL 72 HOUR)
    AND (
      (le.flag = 'abnormal')
      OR (le.valuenum IS NOT NULL AND le.ref_range_lower IS NOT NULL AND le.ref_range_upper IS NOT NULL
          AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper))
    )
  GROUP BY adm.subject_id, adm.hadm_id
),
general_inpatient AS (
  -- General inpatient stats for comparison
  SELECT
    COUNT(*) AS n_admissions,
    AVG(lab_instability_score) AS avg_lab_instability_score,
    APPROX_QUANTILES(lab_instability_score, 2)[OFFSET(1)] AS median_lab_instability_score,
    AVG(los_days) AS avg_los_days,
    APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM (
    SELECT
      adm.subject_id,
      adm.hadm_id,
      TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los_days,
      adm.hospital_expire_flag,
      IFNULL(lab.lab_instability_score, 0) AS lab_instability_score
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
    LEFT JOIN general_inpatient_lab_instability lab
      ON adm.subject_id = lab.subject_id AND adm.hadm_id = lab.hadm_id
  )
)
-- Final output: stats per quintile and general inpatient
SELECT
  'quintile' AS group_type,
  quintile AS group_value,
  n_admissions,
  avg_lab_instability_score,
  median_lab_instability_score,
  avg_los_days,
  median_los_days,
  mortality_rate
FROM quintile_stats
UNION ALL
SELECT
  'general_inpatient' AS group_type,
  NULL AS group_value,
  n_admissions,
  avg_lab_instability_score,
  median_lab_instability_score,
  avg_los_days,
  median_los_days,
  mortality_rate
FROM general_inpatient
ORDER BY group_type, group_value;