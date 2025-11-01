WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 68 AND 78
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.discharge_location
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.admission_location = 'EMERGENCY ROOM'
), CombinedInfo AS (
  SELECT
    pi.subject_id,
    ai.hadm_id,
    ai.admittime,
    ai.dischtime,
    ai.deathtime,
    ai.admission_type,
    ai.admission_location,
    ai.discharge_location
  FROM
    PatientInfo AS pi
  INNER JOIN
    AdmissionInfo AS ai
  ON
    pi.subject_id = ai.subject_id
), LOSCalculation AS (
  SELECT
    ci.hadm_id,
    ci.dischtime,
    ci.deathtime,
    CASE
      WHEN ci.deathtime IS NOT NULL THEN TIMESTAMP_DIFF(ci.deathtime, ci.admittime, DAY)
      ELSE TIMESTAMP_DIFF(ci.dischtime, ci.admittime, DAY)
    END AS los_days
  FROM
    CombinedInfo AS ci
), DischargeStatus AS (
  SELECT
    ci.hadm_id,
    CASE
      WHEN ci.deathtime IS NOT NULL THEN 'DEATH'
      WHEN ci.discharge_location = 'HOME' THEN 'HOME'
      WHEN ci.discharge_location = 'SNF' THEN 'SNF'
      WHEN ci.discharge_location = 'REHAB' THEN 'REHAB'
      WHEN ci.discharge_location = 'HOSPICE' THEN 'HOSPICE'
      ELSE 'OTHER'
    END AS discharge_status
  FROM
    CombinedInfo AS ci
)
SELECT
  ds.discharge_status,
  AVG(lc.los_days) AS mean_los,
  STDDEV(lc.los_days) AS sd_los, -- Changed STDEV to STDDEV
  SUM(CASE WHEN lc.los_days <= 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(lc.los_days) AS percent_los_le_7_days
FROM
  LOSCalculation AS lc
INNER JOIN
  DischargeStatus AS ds
ON
  lc.hadm_id = ds.hadm_id
GROUP BY
  ds.discharge_status
ORDER BY
  ds.discharge_status;