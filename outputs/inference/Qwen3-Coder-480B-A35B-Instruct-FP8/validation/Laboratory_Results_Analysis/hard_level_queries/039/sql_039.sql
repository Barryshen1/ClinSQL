WITH pneumonia_cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours,
    a.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND d.seq_num = 1
    AND LOWER(dd.long_title) LIKE '%pneumonia%'
),

lab_scores AS (
  SELECT
    l.hadm_id,
    l.subject_id,
    STDDEV(l.valuenum) AS instability_score,
    COUNT(CASE WHEN l.flag = 'abnormal' THEN 1 END) AS critical_events
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    pneumonia_cohort pc
    ON l.hadm_id = pc.hadm_id
  WHERE
    l.valuenum IS NOT NULL
    AND l.charttime BETWEEN pc.admittime AND DATETIME_ADD(pc.admittime, INTERVAL 72 HOUR)
    AND l.itemid IN (
      SELECT itemid FROM physionet-data.mimiciv_3_1_hosp.d_labitems
      WHERE LOWER(label) IN (
        'wbc', 'white blood cells', 'hemoglobin', 'hematocrit',
        'platelet count', 'sodium', 'potassium', 'bicarbonate',
        'chloride', 'bun', 'creatinine', 'glucose', 'bilirubin'
      )
    )
  GROUP BY
    l.hadm_id, l.subject_id
),

cohort_stats AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS percentile_75_instability,
    AVG(critical_events) AS mean_critical_events,
    AVG(los_hours) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    pneumonia_cohort pc
  JOIN
    lab_scores ls
    ON pc.hadm_id = ls.hadm_id
),

all_inpatients_critical_events AS (
  SELECT
    AVG(CASE WHEN l.flag = 'abnormal' THEN 1 ELSE 0 END) AS mean_critical_events_all
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  WHERE
    l.valuenum IS NOT NULL
)

SELECT
  cs.percentile_75_instability,
  cs.mean_critical_events,
  aice.mean_critical_events_all,
  cs.mean_los,
  cs.mortality_rate
FROM
  cohort_stats cs
CROSS JOIN
  all_inpatients_critical_events aice;