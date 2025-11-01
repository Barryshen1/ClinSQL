WITH all_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    pt.gender,
    pt.anchor_age,
    pt.anchor_year,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
),

critical_labs AS (
  SELECT
    le.hadm_id,
    COUNT(le.labevent_id) AS critical_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN all_admissions aa
    ON le.hadm_id = aa.hadm_id
  WHERE
    le.charttime BETWEEN aa.admittime AND DATETIME_ADD(aa.admittime, INTERVAL 48 HOUR)
    AND le.flag IS NOT NULL  -- Critical lab defined by non-null flag
  GROUP BY le.hadm_id
),

admissions_with_labs AS (
  SELECT
    aa.*,
    COALESCE(cl.critical_count, 0) AS critical_count,
    aa.anchor_age + (EXTRACT(YEAR FROM aa.admittime) - aa.anchor_year) AS age_at_admission
  FROM all_admissions aa
  LEFT JOIN critical_labs cl
    ON aa.hadm_id = cl.hadm_id
),

hemorrhagic_stroke_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND icd_code IN ('430', '431', '432'))
    OR (icd_version = 10 AND icd_code LIKE 'I6[0-2]%')
),

cohort AS (
  SELECT
    awl.*
  FROM admissions_with_labs awl
  INNER JOIN hemorrhagic_stroke_admissions hsa
    ON awl.hadm_id = hsa.hadm_id
  WHERE
    awl.gender = 'M'
    AND awl.age_at_admission BETWEEN 70 AND 80
),

cohort_stats AS (
  SELECT
    APPROX_QUANTILES(critical_count, 100)[OFFSET(25)] AS percentile_25_score,
    AVG(critical_count) AS cohort_avg_critical_events,
    AVG(los_days) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM cohort
),

general_pop_stats AS (
  SELECT
    AVG(critical_count) AS general_avg_critical_events
  FROM admissions_with_labs
)

SELECT
  cs.percentile_25_score,
  cs.cohort_avg_critical_events,
  gps.general_avg_critical_events,
  cs.mean_los,
  cs.mortality_rate
FROM cohort_stats cs, general_pop_stats gps;