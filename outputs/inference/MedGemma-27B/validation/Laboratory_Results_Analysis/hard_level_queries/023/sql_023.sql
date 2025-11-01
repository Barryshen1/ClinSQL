WITH PatientAMI AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hadm_id,
    d.icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND d.icd_code = 'I21.9' -- AMI code
    AND p.anchor_age BETWEEN 90 AND 100
), PatientLabInstability AS (
  SELECT
    pli.subject_id,
    pli.hadm_id,
    pli.lab_instability_score
  FROM PatientAMI AS ami
  INNER JOIN (
    SELECT
      le.subject_id,
      le.hadm_id,
      SUM(
        CASE
          WHEN ABS(le.value - LAG(le.value, 1, le.value) OVER (PARTITION BY le.subject_id, le.hadm_id, le.itemid ORDER BY le.charttime)) > 0.5 THEN 1
          ELSE 0
        END
      ) AS lab_instability_score
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    WHERE
      le.charttime BETWEEN (
        SELECT
          a.admittime
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        WHERE
          a.hadm_id = le.hadm_id
      ) AND (
        SELECT
          a.admittime
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
        WHERE
          a.hadm_id = le.hadm_id
      ) + INTERVAL '48' HOUR
    GROUP BY
      le.subject_id,
      le.hadm_id
  ) AS pli
    ON ami.subject_id = pli.subject_id
    AND ami.hadm_id = pli.hadm_id
), P75Threshold AS (
  SELECT
    PERCENTILE_CONT(lab_instability_score, 0.75) AS p75_threshold
  FROM PatientLabInstability
), P75Patients AS (
  SELECT
    pli.subject_id,
    pli.hadm_id
  FROM PatientLabInstability AS pli
  INNER JOIN P75Threshold AS p75
    ON pli.lab_instability_score >= p75.p75_threshold
), AllPatients90_100 AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hadm_id,
    a.hospital_expire_flag,
    a.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.anchor_age BETWEEN 90 AND 100
)
SELECT
  p75.subject_id,
  p75.hadm_id,
  AVG(all.hospital_expire_flag) AS in_hospital_mortality,
  AVG(all.los) AS mean_los,
  AVG(all.critical_lab_rates) AS critical_lab_rates
FROM P75Patients AS p75
INNER JOIN AllPatients90_100 AS all
  ON p75.subject_id = all.subject_id
  AND p75.hadm_id = all.hadm_id
GROUP BY
  p75.subject_id,
  p75.;