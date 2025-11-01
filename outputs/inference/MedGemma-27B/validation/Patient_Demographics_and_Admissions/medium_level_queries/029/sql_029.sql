WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 35 AND 45
), ICUAdmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.hadm_id = i.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM PatientAge)
), SurvivalStatus AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    los,
    CASE
      WHEN deathtime IS NOT NULL AND deathtime <= dischtime THEN 'In-hospital death'
      ELSE 'Discharged alive'
    END AS survival_status
  FROM
    ICUAdmissions
)
SELECT
  survival_status,
  AVG(los) AS mean_los,
  STDDEV(los) AS sd_los,
  SUM(CASE WHEN los < 7 THEN 1 ELSE 0 END) * 100.0 / COUNT(los) AS percent_los_less_than_7_days
FROM
  SurvivalStatus
GROUP BY
  survival_status;