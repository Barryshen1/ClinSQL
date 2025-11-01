WITH
  -- Step 1: Identify the cohort of male inpatients aged 87-97
  PatientCohort AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND (
        EXTRACT(
          YEAR
          FROM
            a.admittime
        ) - p.anchor_year
      ) + p.anchor_age BETWEEN 87 AND 97
  ),
  -- Step 2: Calculate the "Lab Instability Score" for each patient in the cohort.
  -- The score is the number of critical lab events in the first 72 hours of admission.
  LabInstabilityScores AS (
    SELECT
      pc.hadm_id,
      pc.admittime,
      pc.dischtime,
      pc.hospital_expire_flag,
      COALESCE(clc.critical_lab_count, 0) AS lab_instability_score
    FROM
      PatientCohort AS pc
    LEFT JOIN (
      SELECT
        le.hadm_id,
        COUNT(le.labevent_id) AS critical_lab_count
      FROM
        `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      INNER JOIN
        PatientCohort AS pc_join
        ON le.hadm_id = pc_join.hadm_id
      WHERE
        le.charttime BETWEEN pc_join.admittime AND DATETIME_ADD(pc_join.admittime, INTERVAL 72 HOUR)
        AND (
          le.valuenum < le.ref_range_lower
          OR le.valuenum > le.ref_range_upper
        )
      GROUP BY
        le.hadm_id
    ) AS clc
      ON pc.hadm_id = clc.hadm_id
  ),
  -- Step 3: Calculate the 95th percentile threshold for the lab instability score
  P95_Threshold AS (
    SELECT
      APPROX_QUANTILES(lab_instability_score, 100) [OFFSET (95)] AS p95_score
    FROM
      LabInstabilityScores
  ),
  -- Step 4: Group patients into 'P95 or above' and 'Below P95' and calculate metrics for each group
  GroupedMetrics AS (
    SELECT
      (
        CASE
          WHEN lis.lab_instability_score >= pt.p95_score
          THEN 'P95_or_above'
          ELSE 'Below_P95'
        END
      ) AS patient_group,
      AVG(lis.lab_instability_score) AS avg_critical_events,
      AVG(DATETIME_DIFF(lis.dischtime, lis.admittime, DAY)) AS mean_los,
      AVG(lis.hospital_expire_flag) AS mortality_rate
    FROM
      LabInstabilityScores AS lis
    CROSS JOIN
      P95_Threshold AS pt
    GROUP BY
      patient_group
  )
-- Final Step: Select and format the results as requested
SELECT
  (
    SELECT
      p95_score
    FROM
      P95_Threshold
  ) AS p95_instability_score_threshold,
  p95.mean_los AS mean_los_for_p95_group,
  p95.mortality_rate AS in_hospital_mortality_for_p95_group,
  p95.avg_critical_events AS avg_critical_events_for_p95_group,
  below_p95.avg_critical_events AS avg_critical_events_for_general_inpatients_in_cohort
FROM
  (
    SELECT
      *
    FROM
      GroupedMetrics
    WHERE
      patient_group = 'P95_or_above'
  ) AS p95
CROSS JOIN
  (
    SELECT
      *
    FROM
      GroupedMetrics
    WHERE
      patient_group = 'Below_P95'
  ) AS below_p95;