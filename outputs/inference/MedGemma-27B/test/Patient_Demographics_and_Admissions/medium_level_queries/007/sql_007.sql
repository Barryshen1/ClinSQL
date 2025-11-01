WITH PatientInfo AS (
  SELECT
    a.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 78 AND 88 AND a.admission_type = 'TRANSFER'
),
AdmissionStats AS (
  SELECT
    subject_id,
    COUNT(hadm_id) AS num_admissions,
    PERCENTILE_CONT(los, 0.5) AS los_p50,
    PERCENTILE_CONT(los, 0.75) AS los_p75,
    PERCENTILE_CONT(los, 0.9) AS los_p90,
    PERCENTILE_CONT(los, 0.95) AS los_p95
  FROM (
    SELECT
      subject_id,
      hadm_id,
      TIMESTAMP_DIFF(dischtime, admit_time, DAY) AS los
    FROM
      PatientInfo
  )
  GROUP BY
    subject_id
),
SurvivalStatus AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN deathtime IS NOT NULL THEN 'In-hospital death'
      ELSE 'Survived'
    END AS survival_status
  FROM
    PatientInfo
),
LOSPercentileRank AS (
  SELECT
    subject_id,
    hadm_id,
    survival_status,
    PERCENTILE_CONT(los, 0.1) AS los_p10
  FROM (
    SELECT
      subject_id,
      hadm_id,
      survival_status,
      TIMESTAMP_DIFF(dischtime, admit_time, DAY) AS los
    FROM
      PatientInfo
    INNER JOIN
      SurvivalStatus
      ON PatientInfo.subject_id = SurvivalStatus.subject_id AND PatientInfo.hadm_id = SurvivalStatus.hadm_id
  )
  GROUP BY
    subject_id,
    hadm_id,
    survival_status
)
SELECT
  SurvivalStatus.survival_status,
  COUNT(DISTINCT AdmissionStats.subject_id) AS number_of_admissions,
  AdmissionStats.los_p50,
  AdmissionStats.los_p75,
  AdmissionStats.los_p90,
  AdmissionStats.los_p95,
  LOSPercentileRank.los_p10 AS percentile_rank_of_10_day_los
FROM
  AdmissionStats
INNER JOIN
  SurvivalStatus
  ON AdmissionStats.subject_id = SurvivalStatus.subject_id
INNER JOIN
  LOSPercentileRank
  ON AdmissionStats.subject_id = LOSPercentileRank.subject_id AND SurvivalStatus.survival_status = LOSPercentileRank.survival_status
GROUP BY
  SurvivalStatus.survival_status,
  AdmissionStats.los_p50,
  AdmissionStats.los_p75,
  AdmissionStats.los_p90,
  AdmissionStats.los_p95,
  LOSPercentileRank.los_p10
ORDER BY
  SurvivalStatus.survival_status;