WITH pneumonia_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    dd.icd_code IN ('J690', 'J189', 'J159', 'J13', 'J14', 'J150', 'J151', 'J158', 'J159', 'J180', 'J181', 'J188')
    AND dd.icd_version = 10
),

eligible_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.deathtime,
    pa.hospital_expire_flag,
    pa.los_days
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  JOIN
    pneumonia_admissions pa
    ON p.subject_id = pa.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),

icu_day1 AS (
  SELECT DISTINCT
    t.hadm_id,
    CASE
      WHEN t.intime <= e.admittime + INTERVAL 1 DAY AND t.outtime >= e.admittime THEN 1
      ELSE 0
    END AS icu_on_day1
  FROM
    physionet-data.mimiciv_3_1_hosp.transfers t
  JOIN
    eligible_patients e
    ON t.hadm_id = e.hadm_id
),

comorbidity_count AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT seq_num) - 1 AS comorbidity_count
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd
  WHERE
    seq_num > 1
  GROUP BY
    hadm_id
),

final_data AS (
  SELECT
    e.hadm_id,
    e.hospital_expire_flag,
    COALESCE(i.icu_on_day1, 0) AS icu_on_day1,
    CASE
      WHEN e.los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN e.los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_group,
    COALESCE(c.comorbidity_count, 0) AS comorbidity_count
  FROM
    eligible_patients e
  LEFT JOIN
    icu_day1 i
    ON e.hadm_id = i.hadm_id
  LEFT JOIN
    comorbidity_count c
    ON e.hadm_id = c.hadm_id
)

SELECT
  los_group,
  icu_on_day1,
  COUNT(*) AS total_patients,
  SUM(hospital_expire_flag) AS deaths,
  AVG(comorbidity_count) AS avg_comorbidity_count,
  ROUND(100 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent
FROM
  final_data
GROUP BY
  los_group,
  icu_on_day1
ORDER BY
  los_group,
  icu_on_day1;