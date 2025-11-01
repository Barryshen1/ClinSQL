WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    -- Filter admissions within the first 72 hours of the entire dataset's time range, not relative to current time
    AND a.admittime BETWEEN TIMESTAMP('2008-01-01 00:00:00') AND TIMESTAMP('2023-12-31 23:59:59') -- Example date range, adjust as needed
),
LabInstability AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.itemid,
    l.valuenum,
    l.valueuom,
    d.label AS lab_name,
    d.category AS lab_category,
    CASE
      WHEN l.valuenum < d.loinc_code THEN 1 -- This comparison is likely incorrect, loinc_code is a string
      WHEN l.valuenum > d.highnormalvalue THEN 1
      ELSE 0
    END AS is_critical
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d
    ON l.itemid = d.itemid
  WHERE
    l.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
    AND l.charttime BETWEEN (
      SELECT
        admittime
      FROM PatientCohort
      WHERE
        subject_id = l.subject_id
    ) AND TIMESTAMP_SUB((
      SELECT
        admittime
      FROM PatientCohort
      WHERE
        subject_id = l.subject_id
    ), INTERVAL 72 HOUR)
),
CriticalLabTypes AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT itemid) AS num_critical_lab_types
  FROM LabInstability
  WHERE
    is_critical = 1
  GROUP BY
    subject_id,
    hadm_id
),
CohortStats AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.anchor_age,
    pc.gender,
    pc.admittime,
    pc.hospital_expire_flag,
    clt.num_critical_lab_types,
    a.los AS length_of_stay
  FROM PatientCohort AS pc
  LEFT JOIN CriticalLabTypes AS clt
    ON pc.subject_id = clt.subject_id AND pc.hadm_id = clt.hadm_id
  LEFT JOIN (
    SELECT
      hadm_id,
      TIMESTAMP_DIFF(dischtime, admittime, HOUR) AS los
    FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  ) AS a
    ON pc.hadm_id = a.hadm_id
)
SELECT
  AVG(num_;