WITH
-- Define the cohort: female patients aged 78-88 with acute ischemic stroke
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND (
      -- ICD-9 codes for acute ischemic stroke
      (d.icd_version = 9 AND d.icd_code LIKE '433.%' AND d.icd_code LIKE '%.1')
      OR (d.icd_version = 9 AND d.icd_code LIKE '434.%' AND d.icd_code LIKE '%.1')
      OR (d.icd_version = 9 AND d.icd_code = '436')
      -- ICD-10 codes for acute ischemic stroke
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I63.%')
    )
),

-- Get lab events within 72 hours of admission for the cohort
cohort_labs AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    l.itemid,
    l.charttime,
    l.valuenum,
    l.valueuom,
    l.ref_range_lower,
    l.ref_range_upper,
    di.label
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON l.itemid = di.itemid
  WHERE
    TIMESTAMP_DIFF(l.charttime, c.admittime, HOUR) <= 72
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
    AND di.category IN ('Chemistry', 'Hematology') -- Focus on critical labs
),

-- Calculate lab instability score for each patient
lab_scores AS (
  SELECT
    subject_id,
    hadm_id,
    SUM(
      CASE
        WHEN valuenum < ref_range_lower THEN POWER(ref_range_lower - valuenum, 2)
        WHEN valuenum > ref_range_upper THEN POWER(valuenum - ref_range_upper, 2)
        ELSE 0
      END
    ) AS instability_score
  FROM
    cohort_labs
  GROUP BY
    subject_id, hadm_id
),

-- Get critical lab events for cohort and general inpatients
critical_lab_events AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNTIF(
      (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      AND di.category IN ('Chemistry', 'Hematology')
    ) AS critical_lab_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON l.itemid = di.itemid
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.subject_id IN (SELECT subject_id FROM cohort)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
  GROUP BY
    a.subject_id, a.hadm_id
),

-- General inpatient comparison group (same age/gender but without stroke)
general_inpatients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNTIF(
      (l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper)
      AND di.category IN ('Chemistry', 'Hematology')
    ) AS critical_lab_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di ON l.itemid = di.itemid
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.subject_id NOT IN (SELECT subject_id FROM cohort)
    AND l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
  GROUP BY
    a.subject_id, a.hadm_id
)

-- Final results
SELECT
  -- Minimum 72-hour lab instability score
  MIN(ls.instability_score) AS min_72h_lab_instability_score,

  -- Average critical lab events comparison
  AVG(cle.critical_lab_count) AS avg_critical_lab_events_cohort,
  (SELECT AVG(critical_lab_count) FROM general_inpatients) AS avg_critical_lab_events_general_inpatients,

  -- Cohort LOS and mortality
  AVG(c.los_hours) AS avg_los_hours,
  SUM(CASE WHEN c.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS mortality_rate

FROM
  cohort c
LEFT JOIN
  lab_scores ls ON c.subject_id = ls.subject_id AND c.hadm_id = ls.hadm_id
LEFT JOIN
  critical_lab_events cle ON c.subject_id = cle.subject_id AND c.hadm_id = cle.hadm_id;