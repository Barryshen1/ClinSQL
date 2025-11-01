WITH cardiac_arrest_cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%cardiac arrest%'
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 52 AND 62
),
lactate_data AS (
  SELECT
    l.valuenum
  FROM cardiac_arrest_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  WHERE
    l.itemid = 50813  -- Lactate
    AND l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
)
SELECT
  (SELECT PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) FROM lactate_data) AS q1,
  (SELECT PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) FROM lactate_data) AS median,
  AVG(DATETIME_DIFF(c.dischtime, c.admittime, HOUR)) AS avg_los_hours,
  AVG(c.hospital_expire_flag) AS mortality_rate
FROM cardiac_arrest_cohort c;