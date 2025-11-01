WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND (
        d.icd_code LIKE '480%' OR d.icd_code LIKE '481%' OR d.icd_code LIKE '482%' OR
        d.icd_code LIKE '483%' OR d.icd_code LIKE '484%' OR d.icd_code LIKE '485%' OR
        d.icd_code LIKE '486%'))
      OR
      (d.icd_version = 10 AND (
        d.icd_code LIKE 'J12%' OR d.icd_code LIKE 'J13%' OR d.icd_code LIKE 'J14%' OR
        d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' OR d.icd_code LIKE 'J17%' OR
        d.icd_code LIKE 'J18%'))
    )
),
lab_instability AS (
  SELECT
    le.hadm_id,
    COUNTIF(
      (le.valuenum IS NOT NULL) AND (
        (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower) OR
        (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper) OR
        (flag IS NOT NULL AND LOWER(flag) IN ('abnormal','high','low'))
      )
    ) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN cohort c ON le.hadm_id = c.hadm_id
  WHERE le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY le.hadm_id
),
critical_events_all AS (
  SELECT
    a.hadm_id,
    COUNTIF(ch.warning = 1) AS critical_event_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON a.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ch
    ON icu.stay_id = ch.stay_id
       AND ch.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY a.hadm_id
),
critical_events_cohort AS (
  SELECT
    c.hadm_id,
    COUNTIF(ch.warning = 1) AS critical_event_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ch
    ON icu.stay_id = ch.stay_id
       AND ch.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
)
SELECT
  APPROX_QUANTILES(l.lab_instability_score, 100)[OFFSET(75)] AS p75_lab_instability_score,
  AVG(cc.critical_event_count) AS mean_critical_event_freq_cohort,
  (SELECT AVG(ca.critical_event_count) FROM critical_events_all ca) AS mean_critical_event_freq_all_inpatients,
  AVG(TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY)) AS mean_los_days_cohort,
  AVG(c.hospital_expire_flag) AS mortality_rate_cohort
FROM cohort c
LEFT JOIN lab_instability l
  ON c.hadm_id = l.hadm_id
LEFT JOIN critical_events_cohort cc
  ON c.hadm_id = cc.hadm_id;