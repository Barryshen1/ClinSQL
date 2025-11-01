WITH 
relevant_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 60 AND 70
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id AND dicd.long_title LIKE '%Pneumonia%' AND d.seq_num = 1
    )
),
lab_instability AS (
  SELECT rp.hadm_id, 
         COUNT(l.labevent_id) AS lab_score -- Simplified count, adjust logic as needed
  FROM relevant_patients rp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON rp.hadm_id = l.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON rp.hadm_id = a.hadm_id
  WHERE l.charttime <= (a.admittime + INTERVAL 72 HOUR)
  GROUP BY rp.hadm_id
),
cohort_analysis AS (
  SELECT 
    PERCENTILE_CONT(lab_score, 0.75) OVER () AS percentile_75_lab_score,
    AVG(a.hospital_expire_flag) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(TIMESTAMP(a.dischtime), TIMESTAMP(a.admittime), HOUR)) AS avg_los_hours
  FROM lab_instability li
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON li.hadm_id = a.hadm_id
),
critical_events AS (
  SELECT rp.hadm_id, COUNT(l.labevent_id) AS critical_event_count
  FROM relevant_patients rp
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON rp.hadm_id = l.hadm_id
  GROUP BY rp.hadm_id
),
all_inpatients_critical_events AS (
  SELECT hadm_id, COUNT(labevent_id) AS critical_event_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents`
  GROUP BY hadm_id
)
SELECT 
  ANY_VALUE(ca.percentile_75_lab_score) AS percentile_75_lab_score,
  ANY_VALUE(ca.mortality_rate) AS mortality_rate,
  ANY_VALUE(ca.avg_los_hours) AS avg_los_hours,
  AVG(ce.critical_event_count) AS mean_critical_event_freq_cohort,
  (SELECT AVG(critical_event_count) FROM all_inpatients_critical_events) AS mean_critical_event_freq_all
FROM cohort_analysis ca
CROSS JOIN critical_events ce;