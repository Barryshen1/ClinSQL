WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id, -- Added hadm_id here
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    l.valuenum AS troponin_t_value,
    l.charttime AS troponin_t_charttime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l
    ON a.hadm_id = l.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
    AND d.label = 'Troponin T'
    AND l.charttime >= a.admittime
    AND l.charttime < a.dischtime
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0 -- Assuming elevated means > 0, adjust if needed
)
SELECT
  COUNT(DISTINCT pc.subject_id) AS patient_count,
  AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS average_length_of_stay_days,
  AVG(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_rate
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` AS a
INNER JOIN
  PatientCohort AS pc
  ON a.hadm_id = pc.hadm_id;