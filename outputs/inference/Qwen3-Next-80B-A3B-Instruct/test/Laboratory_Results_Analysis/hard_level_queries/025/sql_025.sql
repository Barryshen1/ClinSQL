WITH eligible_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did
    ON d.icd_code = did.icd_code AND d.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND (
      did.icd_code IN ('430', '431', '432') -- ICD-9
      OR did.icd_code IN ('I60', 'I61', 'I62') -- ICD-10
    )
),

lab_critical_events AS (
  SELECT
    ep.subject_id,
    dl.category,
    le.valuenum,
    le.ref_range_lower,
    le.ref_range_upper,
    le.charttime
  FROM eligible_patients ep
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ep.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND le.charttime >= ep.admittime
    AND le.charttime <= TIMESTAMP_ADD(ep.admittime, INTERVAL 72 HOUR)
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
),

lab_instability_score AS (
  SELECT
    subject_id,
    COUNT(DISTINCT category) AS lab_instability_score
  FROM lab_critical_events
  GROUP BY subject_id
),

p90_threshold AS (
  SELECT PERCENTILE_CONT(lab_instability_score, 0.9) AS p90_score
  FROM lab_instability_score
),

flagged_patients AS (
  SELECT
    ep.subject_id,
    ep.hadm_id,
    ep.admittime,
    ep.dischtime,
    ep.hospital_expire_flag,
    lis.lab_instability_score,
    CASE
      WHEN lis.lab_instability_score >= p90.p90_score THEN 'Above_P90'
      ELSE 'Cohort'
    END AS group_label
  FROM eligible_patients ep
  JOIN lab_instability_score lis
    ON ep.subject_id = lis.subject_id
  CROSS JOIN p90_threshold p90
)

SELECT
  group_label AS group,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los_days,
  AVG(lab_instability_score) AS avg_critical_labs_per_patient
FROM flagged_patients
GROUP BY group_label
ORDER BY group_label;