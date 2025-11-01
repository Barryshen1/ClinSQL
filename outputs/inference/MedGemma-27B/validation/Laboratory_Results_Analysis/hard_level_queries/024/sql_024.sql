WITH PatientCohort AS (
  -- Select patients meeting the criteria: female, age 53-63, post-cardiac arrest
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.admission_type = 'EMERGENCY' -- Assuming cardiac arrest usually presents as emergency admission
    AND EXISTS (
      SELECT
        1
      FROM
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I46%' -- ICD-10 code for Cardiac arrest
    )
),
LabInstabilityScore AS (
  -- Calculate the lab instability score for each patient within the first 48 hours
  SELECT
    pc.subject_id,
    pc.hadm_id,
    SUM(
      CASE
        WHEN ABS(le.value - le.ref_range_lower) > 0.5 * (le.ref_range_upper - le.ref_range_lower) THEN 1
        ELSE 0
      END
    ) AS instability_score
  FROM
    PatientCohort AS pc
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON pc.subject_id = le.subject_id
    AND pc.hadm_id = le.hadm_id
  WHERE
    le.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 48 HOUR)
    AND le.itemid IN (
      -- Select relevant lab items (e.g., electrolytes, coagulation, cardiac markers)
      SELECT
        itemid
      FROM
        `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE
        category = 'Electrolytes'
        OR category = 'Coagulation'
        OR category = 'Cardiac Markers'
        OR category = 'Blood Gas'
    )
  GROUP BY
    pc.subject_id,
    pc.hadm_id
),
PercentileThreshold AS (
  -- Calculate the 90th percentile of the instability score
  SELECT
    PERCENTILE_CONT(instability_score, 0.90) AS percentile_90
  FROM
    LabInstabilityScore
),
HighInstabilityCohort AS (
  -- Select patients with instability score >= 90th percentile
  SELECT
    lis.subject_id,
    lis.hadm_id,
    lis.instability_score
  FROM
    LabInstabilityScore AS lis
  CROSS JOIN
    PercentileThreshold AS pt
  WHERE
    lis.instability_score >= pt.percentile_90
),
CohortStats AS (
  -- Calculate statistics for the high instability cohort
  SELECT
    COUNT(DISTINCT subject_id) AS patient_count,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS mortality_count,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS mean_los_days
  FROM
    HighInstabilityCohort AS hic
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON hic.subject_id = a.subject_id
    AND hic.hadm_id = a.hadm_id
),
CriticalLabFrequency AS (
  -- Calculate the frequency of critical labs for the high instability cohort
  SELECT
    COUNT(DISTINCT le.itemid) AS critical_lab_count
  FROM
    HighInstabilityCohort AS hic
  INNER JOIN
    `physionet-data.mimiciv;