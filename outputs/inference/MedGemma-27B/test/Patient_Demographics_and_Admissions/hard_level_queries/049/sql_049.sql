WITH IndexAdmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.insurance,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    d.long_title AS principal_diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 61 AND 71
    AND a.admission_location = 'SNF'
    AND a.insurance = 'Medicare'
    AND d.icd_code LIKE 'N17%' -- Acute kidney injury
), Readmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        IndexAdmissions
    )
    AND a.admittime > (
      SELECT
        MAX(dischtime)
      FROM
        IndexAdmissions
      WHERE
        IndexAdmissions.subject_id = a.subject_id
    )
), IndexLOS AS (
  SELECT
    hadm_id,
    subject_id,
    CASE
      WHEN deathtime IS NOT NULL THEN deathtime
      ELSE dischtime
    END AS discharge_time,
    TIMESTAMP_DIFF(CASE WHEN deathtime IS NOT NULL THEN deathtime ELSE dischtime END, admittime, DAY) AS los_days
  FROM
    IndexAdmissions
), ReadmissionLOS AS (
  SELECT
    hadm_id,
    subject_id,
    CASE
      WHEN deathtime IS NOT NULL THEN deathtime
      ELSE dischtime
    END AS discharge_time,
    TIMESTAMP_DIFF(CASE WHEN deathtime IS NOT NULL THEN deathtime ELSE dischtime END, admittime, DAY) AS los_days
  FROM
    Readmissions
)
SELECT
  COUNT(DISTINCT r.subject_id) AS num_readmitted,
  (
    COUNT(DISTINCT r.subject_id) / COUNT(DISTINCT i.subject_id)
  ) * 100 AS readmission_rate_percent,
  AVG(rl.los_days) AS median_readmission_los,
  AVG(il.los_days) AS median_index_los,
  SUM(CASE WHEN il.los_days > 6 THEN 1 ELSE 0 END) / COUNT(DISTINCT i.subject_id) * 100 AS percent_index_stays_gt_6_days
FROM
  IndexAdmissions AS i
LEFT JOIN
  Readmissions AS r
  ON i.subject_id = r.subject_id
LEFT JOIN
  IndexLOS AS il
  ON i.hadm_id = il.hadm_id
LEFT JOIN
  ReadmissionLOS AS rl
  ON r.hadm_id =;