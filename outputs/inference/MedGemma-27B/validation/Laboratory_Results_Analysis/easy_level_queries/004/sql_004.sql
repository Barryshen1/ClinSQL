WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.admission_type,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 76
    AND d.icd_code = 'A41.9' -- Sepsis code
),
PlateletCounts AS (
  SELECT
    pc.subject_id,
    pc.charttime,
    pc.valuenum AS platelet_count
  FROM
    PatientCohort AS pc
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON pc.subject_id = le.subject_id
    AND pc.hadm_id = le.hadm_id
  WHERE
    le.itemid = 50984 -- Platelet count itemid
    AND le.charttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 24 HOUR)
),
AveragePlateletCounts AS (
  SELECT
    subject_id,
    AVG(platelet_count) AS avg_platelet_count
  FROM
    PlateletCounts
  GROUP BY
    subject_id
)
SELECT
  AVG(avg_platelet_count) AS median_platelet_count
FROM
  AveragePlateletCounts;